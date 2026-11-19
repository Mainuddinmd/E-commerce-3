// ============================================================================
//  MyShop Backend  -  server.js  (Node.js + Express + MongoDB)
// ============================================================================
//  এই ফাইলটাই Flutter অ্যাপ আর MongoDB-র মাঝখানের "সেতু"।
//  কারণ: browser (Flutter Web) সরাসরি MongoDB-তে যেতে পারে না।
//
//  চালানোর নিয়ম (টার্মিনালে, এই ফাইলের ফোল্ডারে):
//     npm init -y
//     npm install express cors mongodb
//     node server.js
//
//  👇👇👇 আপনাকে শুধু নিচের MONGODB_URI-তে key বসাতে হবে 👇👇👇
// ============================================================================

const MONGODB_URI = 'mongodb+srv://mdmain70693_db_user:mdmain70693_db_user@cluster0.i9gfejp.mongodb.net/'; // <-- 👈 এখানে আপনার MongoDB key বসান (দুই কোটেশনের ভেতরে)

// Cloudinary (admin media upload)
const CLOUDINARY_CLOUD_NAME = 'k17ycpgb';
const CLOUDINARY_API_KEY = '828555762225295';
const CLOUDINARY_API_SECRET = 'MLJqeTl6lEGL4451GKJ4ohMCIwQ';

//   উদাহরণ: 'mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/'

const DB_NAME = 'myshop'; // database এর নাম (না থাকলে নিজে তৈরি হবে)
const PORT = 3000;

// প্রথমবার চালালে এই Admin অ্যাকাউন্ট তৈরি হবে। পরে অবশ্যই পাসওয়ার্ড বদলে নিন।
const ADMIN_EMAIL = 'admin@shop.com';
const ADMIN_PASSWORD = 'admin123';

// ============================================================================

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const { MongoClient } = require('mongodb');
const multer = require('multer');
const { v2: cloudinary } = require('cloudinary');

cloudinary.config({
  cloud_name: CLOUDINARY_CLOUD_NAME,
  api_key: CLOUDINARY_API_KEY,
  api_secret: CLOUDINARY_API_SECRET,
});

// Multer (in-memory) for admin media uploads
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50 MB
  fileFilter: (req, file, cb) => {
    const mt = (file.mimetype || '').toLowerCase();
    const name = (file.originalname || '').toLowerCase();
    const okMime = mt.startsWith('image/') || mt.startsWith('video/') || mt === 'application/octet-stream';
    const okExt = /\.(jpg|jpeg|png|gif|webp|bmp|svg|mp4|mov|webm|mkv|avi)$/i.test(name);
    if (okMime || okExt) cb(null, true);
    else cb(new Error('Only image or video files are allowed'));
  },
});

const app = express();
app.use(cors()); // শেখার সময় সব জায়গা থেকে অনুমতি দেওয়া হয়েছে
app.use(express.json({ limit: '2mb' }));

let db;
const sessions = new Map(); // token -> userId  (সার্ভার restart দিলে সবাই logout হবে)

// ---------- ছোট সাহায্যকারী ----------
let lastId = 0;
const newId = () => {
  lastId = Math.max(Date.now() * 10, lastId + 1);
  return lastId;
};
const today = () => new Date().toISOString().slice(0, 10);
const fail = (res, msg, code = 400) => res.status(code).json({ error: msg });
const wrap = (fn) => (req, res, next) =>
  fn(req, res, next).catch((e) => {
    console.error(e);
    res.status(500).json({ error: 'Server error' });
  });

// পাসওয়ার্ড কখনো সরাসরি রাখা হয় না, hash করে রাখা হয়
function hashPassword(pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  return salt + ':' + crypto.scryptSync(pw, salt, 64).toString('hex');
}
function checkPassword(pw, stored) {
  if (!stored) return false;
  const [salt, hash] = stored.split(':');
  const test = crypto.scryptSync(pw, salt, 64);
  return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), test);
}

const publicUser = (u) => ({
  id: u.id, name: u.name, email: u.email, phone: u.phone || '', address: u.address || '',
  membership: u.membership || 'None', isAdmin: !!u.isAdmin, blocked: !!u.blocked,
});

function startSession(user) {
  const token = crypto.randomBytes(24).toString('hex');
  sessions.set(token, user.id);
  return { token, user: publicUser(user) };
}

// ---------- লগইন চেক (middleware) ----------
async function auth(req, res, next) {
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  const uid = sessions.get(token);
  if (!uid) return fail(res, 'Please login again', 401);
  const user = await db.collection('users').findOne({ id: uid });
  if (!user || user.blocked) return fail(res, 'Please login again', 401);
  req.user = user;
  next();
}
const adminOnly = (req, res, next) => (req.user.isAdmin ? next() : fail(res, 'Admin only', 403));

// ---------- Settings পরিষ্কার করা ----------
const SETTING_TEXT = ['siteName', 'logoText', 'logoUrl', 'tagline', 'announcement', 'footerText', 'currency',
  'siteUrl', 'whatsapp', 'bkashNumber', 'contactEmail', 'contactPhone', 'contactAddress'];

function cleanSettings(b) {
  const o = {};
  for (const k of SETTING_TEXT) if (b[k] !== undefined) o[k] = String(b[k]);
  if (b.showAnnouncement !== undefined) o.showAnnouncement = !!b.showAnnouncement;
  if (b.primaryColor !== undefined) o.primaryColor = Number(b.primaryColor) || 0xFF1E88E5;
  if (b.perPage !== undefined) o.perPage = Math.max(1, Math.floor(Number(b.perPage)) || 6);
  if (b.deliveryFee !== undefined) o.deliveryFee = Math.max(0, Number(b.deliveryFee) || 0);
  if (Array.isArray(b.categories)) o.categories = b.categories.map(String);
  if (Array.isArray(b.links)) o.links = b.links.map((l) => ({ label: String(l.label || ''), url: String(l.url || '') }));
  return o;
}

// ============================================================================
//  PUBLIC API (লগইন ছাড়াই)
// ============================================================================
app.get('/api/health', (req, res) => res.json({ ok: true }));

app.get('/api/data', wrap(async (req, res) => {
  const P = { projection: { _id: 0 } };
  res.json({
    settings: await db.collection('settings').findOne({ _id: 'main' }, P),
    products: await db.collection('products').find({}, P).sort({ id: -1 }).toArray(),
    slides: await db.collection('slides').find({}, P).sort({ id: 1 }).toArray(),
    memberships: await db.collection('memberships').find({}, P).sort({ id: 1 }).toArray(),
    reviews: await db.collection('reviews').find({ approved: true }, P).toArray(), // শুধু approved
  });
}));

app.post('/api/register', wrap(async (req, res) => {
  const name = String(req.body.name || '').trim();
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  if (!name || !email.includes('@') || password.length < 6) {
    return fail(res, 'Name, a valid email and a password (6+ characters) are required');
  }
  const users = db.collection('users');
  if (await users.findOne({ email })) return fail(res, 'This email is already registered');
  const user = {
    id: newId(), name, email, phone: String(req.body.phone || ''), address: '',
    membership: 'None', isAdmin: false, blocked: false, passwordHash: hashPassword(password),
  };
  await users.insertOne({ ...user });
  res.json(startSession(user));
}));

app.post('/api/login', wrap(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const user = await db.collection('users').findOne({ email });
  if (!user || !checkPassword(String(req.body.password || ''), user.passwordHash)) return fail(res, 'Wrong email or password');
  if (user.blocked) return fail(res, 'Your account is blocked. Contact support.');
  if (req.body.adminOnly && !user.isAdmin) return fail(res, 'This account is not an admin');
  res.json(startSession(user));
}));

// ============================================================================
//  CUSTOMER API (লগইন লাগবে)
// ============================================================================
app.put('/api/me', auth, wrap(async (req, res) => {
  const set = {
    name: String(req.body.name || req.user.name),
    phone: String(req.body.phone || ''),
    address: String(req.body.address || ''),
  };
  const pw = String(req.body.password || '');
  if (pw) {
    if (pw.length < 6) return fail(res, 'Password must be at least 6 characters');
    set.passwordHash = hashPassword(pw);
  }
  await db.collection('users').updateOne({ id: req.user.id }, { $set: set });
  res.json(publicUser(await db.collection('users').findOne({ id: req.user.id })));
}));

app.post('/api/me/membership', auth, wrap(async (req, res) => {
  const plan = await db.collection('memberships').findOne({ name: String(req.body.name || '') });
  if (!plan) return fail(res, 'Plan not found');
  // Demo: এখানে আসল পেমেন্ট নেওয়ার কথা
  await db.collection('users').updateOne({ id: req.user.id }, { $set: { membership: plan.name } });
  res.json(publicUser(await db.collection('users').findOne({ id: req.user.id })));
}));

app.get('/api/my/orders', auth, wrap(async (req, res) => {
  const list = await db.collection('orders').find({ userId: req.user.id }, { projection: { _id: 0 } }).sort({ id: -1 }).toArray();
  res.json(list);
}));

app.post('/api/orders', auth, wrap(async (req, res) => {
  const { name, phone, address, payment, trxId, items } = req.body;
  if (!name || !phone || !address) return fail(res, 'Name, phone and address are required');
  if (!['COD', 'bKash'].includes(payment)) return fail(res, 'Invalid payment method');
  if (payment === 'bKash' && !trxId) return fail(res, 'bKash Transaction ID is required');
  if (!Array.isArray(items) || items.length === 0) return fail(res, 'Cart is empty');

  const products = db.collection('products');
  const taken = [];
  const lines = [];
  let subtotal = 0;
  try {
    for (const it of items) {
      const qty = Math.floor(Number(it.qty));
      const pid = Number(it.productId);
      if (!(qty > 0)) throw new Error('Invalid quantity');
      const p = await products.findOne({ id: pid });
      if (!p) throw new Error('A product is no longer available');
      // stock কমানো (যথেষ্ট stock না থাকলে modifiedCount = 0)
      const r = await products.updateOne({ id: pid, stock: { $gte: qty } }, { $inc: { stock: -qty } });
      if (r.modifiedCount === 0) throw new Error('Not enough stock for ' + p.name);
      taken.push({ pid, qty });
      // দাম সবসময় database থেকে নেওয়া হয়, ব্যবহারকারীর পাঠানো দাম বিশ্বাস করা হয় না
      lines.push({ productId: pid, name: p.name, price: p.price, qty });
      subtotal += p.price * qty;
    }
  } catch (e) {
    for (const t of taken) await products.updateOne({ id: t.pid }, { $inc: { stock: t.qty } }); // ফেরত
    return fail(res, e.message);
  }
  const settings = await db.collection('settings').findOne({ _id: 'main' });
  const plan = await db.collection('memberships').findOne({ name: req.user.membership });
  const discount = plan ? plan.discount : 0;
  const total = subtotal - (subtotal * discount) / 100 + (settings.deliveryFee || 0);
  const order = {
    id: newId(), userId: req.user.id, userEmail: req.user.email, userName: String(name), phone: String(phone),
    address: String(address), payment, trxId: String(trxId || ''), status: 'Pending', date: today(),
    items: lines, total: Math.round(total * 100) / 100, returnRequested: false, returnReason: '',
  };
  await db.collection('orders').insertOne({ ...order });
  res.json(order);
}));

app.post('/api/orders/:id/return', auth, wrap(async (req, res) => {
  const orders = db.collection('orders');
  const o = await orders.findOne({ id: Number(req.params.id), userId: req.user.id });
  if (!o) return fail(res, 'Order not found', 404);
  if (o.status !== 'Delivered' || o.returnRequested) return fail(res, 'Return is not possible for this order');
  await orders.updateOne({ id: o.id }, { $set: { returnRequested: true, returnReason: String(req.body.reason || '') } });
  res.json({ ok: true });
}));

app.post('/api/reviews', auth, wrap(async (req, res) => {
  const pid = Number(req.body.productId);
  const rating = Math.min(5, Math.max(1, Math.floor(Number(req.body.rating)) || 5));
  const comment = String(req.body.comment || '').trim();
  if (!comment) return fail(res, 'Write a comment first');
  if (!(await db.collection('products').findOne({ id: pid }))) return fail(res, 'Product not found', 404);
  await db.collection('reviews').insertOne({
    id: newId(), productId: pid, rating, userName: req.user.name, comment, approved: false, // admin approve করলে দেখাবে
  });
  res.json({ ok: true });
}));

// ============================================================================
//  ADMIN API (শুধু admin)
// ============================================================================
app.get('/api/admin/data', auth, adminOnly, wrap(async (req, res) => {
  const P = { projection: { _id: 0 } };
  res.json({
    users: await db.collection('users').find({}, { projection: { _id: 0, passwordHash: 0 } }).toArray(),
    orders: await db.collection('orders').find({}, P).sort({ id: -1 }).toArray(),
    reviews: await db.collection('reviews').find({}, P).toArray(), // approved + pending সব
  });
}));

app.put('/api/admin/settings', auth, adminOnly, wrap(async (req, res) => {
  await db.collection('settings').updateOne({ _id: 'main' }, { $set: cleanSettings(req.body) });
  res.json({ ok: true });
}));

// কোন collection-এর কোন field Admin বদলাতে পারবে
const FIELDS = {
  products: ['name', 'price', 'oldPrice', 'category', 'desc', 'imageUrl', 'extUrl', 'stock', 'colorValue', 'mediaType', 'publicId'],
  slides: ['title', 'subtitle', 'buttonText', 'imageUrl', 'category', 'colorValue', 'mediaType', 'publicId'],
  memberships: ['name', 'price', 'discount', 'perks'],
  reviews: ['approved'],
  orders: ['status'],
};
const NUMERIC = new Set(['price', 'oldPrice', 'stock', 'colorValue', 'discount']);
const CAN_CREATE = new Set(['products', 'slides', 'memberships']); // reviews/orders নতুন তৈরি হয় না
const ORDER_STATUSES = ['Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled', 'Returned'];

function cleanItem(col, item) {
  const o = {};
  for (const f of FIELDS[col]) {
    if (item[f] === undefined) continue;
    if (NUMERIC.has(f)) o[f] = Number(item[f]) || 0;
    else if (f === 'approved') o[f] = !!item[f];
    else o[f] = String(item[f]);
  }
  if (col === 'orders' && o.status && !ORDER_STATUSES.includes(o.status)) throw new Error('Invalid status');
  return o;
}

async function upsertUsers(items, selfId) {
  const col = db.collection('users');
  for (const it of items) {
    const id = Number(it.id);
    const email = String(it.email || '').trim().toLowerCase();
    if (!id || !email || !String(it.name || '').trim()) throw new Error('Name and email are required');
    const existing = await col.findOne({ id });
    const doc = {
      name: String(it.name), email, phone: String(it.phone || ''), address: String(it.address || ''),
      membership: String(it.membership || 'None'), isAdmin: !!it.isAdmin, blocked: !!it.blocked,
    };
    if (id === selfId) { doc.isAdmin = true; doc.blocked = false; } // নিজেকে lock-out করা যাবে না
    if (it.password) {
      if (String(it.password).length < 6) throw new Error('Password must be at least 6 characters');
      doc.passwordHash = hashPassword(String(it.password));
    } else if (!existing) throw new Error('Password is required for a new user');
    if (await col.findOne({ email, id: { $ne: id } })) throw new Error('Email already used: ' + email);
    await col.updateOne({ id }, { $set: doc }, { upsert: true });
  }
}

app.post('/api/admin/:col/upsert', auth, adminOnly, wrap(async (req, res) => {
  const col = req.params.col;
  const items = Array.isArray(req.body.items) ? req.body.items : [];
  try {
    if (col === 'users') {
      await upsertUsers(items, req.user.id);
    } else if (FIELDS[col]) {
      for (const it of items) {
        const id = Number(it.id);
        if (!id) continue;
        await db.collection(col).updateOne({ id }, { $set: cleanItem(col, it) }, { upsert: CAN_CREATE.has(col) });
      }
    } else return fail(res, 'Unknown collection', 404);
  } catch (e) {
    return fail(res, e.message);
  }
  res.json({ ok: true });
}));

app.post('/api/admin/:col/delete', auth, adminOnly, wrap(async (req, res) => {
  const col = req.params.col;
  if (col !== 'users' && !FIELDS[col]) return fail(res, 'Unknown collection', 404);
  let ids = (Array.isArray(req.body.ids) ? req.body.ids : []).map(Number);
  if (col === 'users') ids = ids.filter((id) => id !== req.user.id); // নিজেকে delete করা যাবে না
  await db.collection(col).deleteMany({ id: { $in: ids } });
  res.json({ ok: true });
}));

app.post('/api/admin/upload', auth, adminOnly, upload.single('file'), wrap(async (req, res) => {
  if (!req.file) return fail(res, 'No file uploaded');
  const dataUri = `data:${req.file.mimetype};base64,${req.file.buffer.toString('base64')}`;
  const result = await cloudinary.uploader.upload(dataUri, {
    resource_type: 'auto',
    folder: 'myshop',
    transformation: [{ quality: 'auto', fetch_format: 'auto' }],
  });
  const optimizedUrl = (result.secure_url || '').replace(/\/upload\//, '/upload/q_auto,f_auto/');
  res.json({
    url: optimizedUrl,
    secure_url: optimizedUrl,
    public_id: result.public_id,
    resource_type: result.resource_type,
    format: result.format,
    width: result.width,
    height: result.height,
    bytes: result.bytes,
    duration: result.duration,
  });
}));

// Express error handler for multer / upload errors
app.use((err, req, res, next) => {
  console.error(err);
  res.status(400).json({ error: (err && err.message) ? err.message : 'Upload failed' });
});

// ============================================================================
//  প্রথমবার চালালে নমুনা ডাটা তৈরি
// ============================================================================
async function seed() {
  const settings = db.collection('settings');
  if (!(await settings.findOne({ _id: 'main' }))) {
    console.log('🌱 প্রথমবার: নমুনা ডাটা তৈরি হচ্ছে...');
    await settings.insertOne({
      _id: 'main', siteName: 'MyShop', logoText: '🛍️', logoUrl: '', tagline: 'Your trusted online shop',
      announcement: '🎉 Free delivery on orders above 2000!', showAnnouncement: true,
      footerText: '© 2026 MyShop. All rights reserved.', currency: '৳', siteUrl: 'https://myshop.example.com',
      primaryColor: 0xFF1E88E5, whatsapp: '8801700000000', bkashNumber: '01700000000',
      contactEmail: 'support@myshop.com', contactPhone: '+880 1700-000000', contactAddress: 'Chattogram, Bangladesh',
      perPage: 6, deliveryFee: 60,
      categories: ['Fashion', 'Electronics', 'Home & Living', 'Beauty', 'Grocery'],
      links: [{ label: 'Facebook', url: 'https://facebook.com/myshop' }, { label: 'Daraz Store', url: 'https://daraz.com.bd' }],
    });

    await db.collection('memberships').insertMany([
      { id: newId(), name: 'Silver', price: 500, discount: 5, perks: '5% discount on every order' },
      { id: newId(), name: 'Gold', price: 1000, discount: 10, perks: '10% discount + priority support' },
      { id: newId(), name: 'Platinum', price: 2000, discount: 15, perks: '15% discount + free gifts' },
    ]);

    await db.collection('slides').insertMany([
      { id: newId(), title: 'Mega Sale is Live!', subtitle: 'Up to 50% off on Fashion', buttonText: 'Shop Fashion', imageUrl: '', category: 'Fashion', colorValue: 0xFFE53935 },
      { id: newId(), title: 'New Gadgets Arrived', subtitle: 'Latest electronics at best price', buttonText: 'Explore', imageUrl: '', category: 'Electronics', colorValue: 0xFF1E88E5 },
      { id: newId(), title: 'Make Your Home Beautiful', subtitle: 'Decor & essentials', buttonText: 'View Home', imageUrl: '', category: 'Home & Living', colorValue: 0xFF43A047 },
    ]);

    const p = (name, price, oldPrice, category, colorValue, desc, stock = 12) =>
      ({ name, price, oldPrice, category, colorValue, desc, stock, imageUrl: '', extUrl: '' });
    const list = [
      p('Cotton T-Shirt', 450, 600, 'Fashion', 0xFFE53935, 'Soft 100% cotton t-shirt, available in many sizes.'),
      p('Denim Jacket', 1800, 2400, 'Fashion', 0xFF1E88E5, 'Classic denim jacket for all seasons.'),
      p('Running Shoes', 2200, 2800, 'Fashion', 0xFFFB8C00, 'Lightweight and comfortable running shoes.'),
      p('Wireless Earbuds', 1500, 2000, 'Electronics', 0xFF8E24AA, 'Bluetooth 5.3, 24 hours battery life.'),
      p('Smart Watch', 3200, 4000, 'Electronics', 0xFF00897B, 'Heart-rate, steps and notifications.'),
      p('Power Bank 20000mAh', 1900, 0, 'Electronics', 0xFF6D4C41, 'Fast charging power bank.', 4),
      p('Table Lamp', 650, 800, 'Home & Living', 0xFFFB8C00, 'Modern LED table lamp.'),
      p('Bed Sheet Set', 1200, 1500, 'Home & Living', 0xFFD81B60, 'Double bed sheet with 2 pillow covers.'),
      p('Face Wash', 350, 0, 'Beauty', 0xFF43A047, 'Gentle daily face wash.'),
      p('Lipstick Matte', 520, 650, 'Beauty', 0xFFE53935, 'Long-lasting matte lipstick.'),
      p('Basmati Rice 5kg', 850, 0, 'Grocery', 0xFF6D4C41, 'Premium quality basmati rice.'),
      p('Olive Oil 500ml', 980, 1100, 'Grocery', 0xFF43A047, 'Extra virgin olive oil.'),
      p('Backpack', 1100, 1400, 'Fashion', 0xFF00897B, 'Water-resistant laptop backpack.'),
      p('Bluetooth Speaker', 2100, 2600, 'Electronics', 0xFF1E88E5, 'Portable speaker with deep bass.'),
    ];
    list[0].extUrl = 'https://daraz.com.bd';
    // তালিকার প্রথম পণ্য সবচেয়ে বড় id পাবে (যাতে সবার উপরে দেখায়)
    const docs = [...list].reverse().map((x) => ({ id: newId(), ...x }));
    await db.collection('products').insertMany(docs);
    const byName = (n) => docs.find((d) => d.name === n).id;
    await db.collection('reviews').insertMany([
      { id: newId(), productId: byName('Cotton T-Shirt'), rating: 5, userName: 'Rahim', comment: 'Very good quality!', approved: true },
      { id: newId(), productId: byName('Wireless Earbuds'), rating: 4, userName: 'Karim', comment: 'Sound is great.', approved: true },
      { id: newId(), productId: byName('Wireless Earbuds'), rating: 3, userName: 'Sumi', comment: 'Okay for the price.', approved: false },
    ]);
  }

  const users = db.collection('users');
  if (!(await users.findOne({ isAdmin: true }))) {
    await users.insertOne({
      id: newId(), name: 'Admin', email: ADMIN_EMAIL.toLowerCase(), phone: '', address: '',
      membership: 'None', isAdmin: true, blocked: false, passwordHash: hashPassword(ADMIN_PASSWORD),
    });
    console.log(`👤 Admin তৈরি হয়েছে: ${ADMIN_EMAIL}  (পাসওয়ার্ড: ADMIN_PASSWORD এর মান)`);
  }
}

// ============================================================================
//  চালু করা
// ============================================================================
async function main() {
  if (!MONGODB_URI) {
    console.error('❌ MONGODB_URI খালি! server.js ফাইলের উপরে আপনার MongoDB key বসান।');
    process.exit(1);
  }
  const client = new MongoClient(MONGODB_URI);
  await client.connect();
  db = client.db(DB_NAME);
  await db.collection('users').createIndex({ email: 1 }, { unique: true });
  await seed();
  app.listen(PORT, () => console.log(`✅ MongoDB connected. Server running: http://localhost:${PORT}`));
}

main().catch((e) => {
  console.error('❌ Could not start:', e.message);
  console.error('   -> key ঠিক আছে? Atlas -> Network Access এ আপনার IP allow করা আছে?');
  process.exit(1);
});
