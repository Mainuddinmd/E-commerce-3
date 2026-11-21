// ============================================================================
//  MyShop  -  Single File E-commerce (Flutter + Dart)  +  MongoDB (via server.js)
// ============================================================================
//  এই ফাইলে MongoDB key নেই! key থাকে শুধু server.js ফাইলে।
//  এই ফাইলে আপনাকে শুধু নিচের apiBaseUrl দেখতে হবে (সার্ভারের ঠিকানা)।
//
//  চালানোর নিয়ম:
//   1. আগে server.js চালু করুন (node server.js)
//   2. টার্মিনালে:  flutter pub add http
//   3. তারপর:       flutter run -d chrome
//
//  Admin Login (server.js প্রথমবার চালালে তৈরি হয়):
//   admin@shop.com / admin123   (server.js এ বদলানো যায়)
//
//  ফাইলের গঠন:
//   1. MODELS      -> ডাটার আকার + JSON (database এর সাথে আদান-প্রদানের ভাষা)
//   2. API         -> server.js এর সাথে কথা বলার অংশ
//   3. STORE       -> অ্যাপের ডাটা। Admin কিছু বদলালে নিজে নিজে database এ save হয়
//   4. HELPERS     -> ছোট সাহায্যকারী ফাংশন/উইজেট
//   5. FRONTEND    -> Home, Product, Cart, Checkout, Login, Register, Profile
//   6. ADMIN PANEL -> Dashboard, Branding, Hero, Products, Categories ...
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

// 👇 সার্ভারের ঠিকানা। নিজের কম্পিউটারে চালালে এটাই থাকবে।
//    পরে server অনলাইনে দিলে এখানে সেই ঠিকানা বসাবেন (যেমন https://myshop-api.onrender.com)
String get apiBaseUrl {
  const raw = String.fromEnvironment('apiBaseUrl', defaultValue: 'http://localhost:3000');
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

// Backend keep-alive: pings /api/health every 10 min to keep Render awake.
class _BackendKeepAlive with WidgetsBindingObserver {
  Timer? _timer;
  bool _active = true;
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => _ping());
    WidgetsBinding.instance.addObserver(this);
  }
  Future<void> _ping() async {
    if (!_active) return;
    try {
      await http.get(Uri.parse('$apiBaseUrl/api/health'));
    } catch (_) {}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _ping();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _active = false;
    }
  }
  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}

final _keepAlive = _BackendKeepAlive();

void main() {
  runApp(const ShopApp());
  store.loadPublic(); // অ্যাপ চালু হলেই database থেকে ডাটা আনা শুরু
  _keepAlive.start();
}

// ============================================================================
// 1. MODELS
// ============================================================================

// JSON থেকে মান পড়ার ছোট সাহায্যকারী (মান না থাকলে ফাঁকা/০ দেয়, ক্র্যাশ করে না)
String _s(Map j, String k) => (j[k] ?? '').toString();
double _d(Map j, String k) => ((j[k] ?? 0) as num).toDouble();
int _i(Map j, String k) => ((j[k] ?? 0) as num).toInt();
bool _b(Map j, String k) => j[k] == true;

class Product {
  int id;
  String name;
  double price;
  double oldPrice;
  String category;
  String desc;
  String imageUrl;
  String mediaType; // 'image' or 'video'
  String publicId; // Cloudinary public_id
  String extUrl; // Third-party / partner লিংক
  int stock;
  int colorValue;
  Product({
    required this.id,
    required this.name,
    required this.price,
    this.oldPrice = 0,
    required this.category,
    this.desc = '',
    this.imageUrl = '',
    this.mediaType = 'image',
    this.publicId = '',
    this.extUrl = '',
    this.stock = 10,
    this.colorValue = 0xFF42A5F5,
  });
  factory Product.fromJson(Map j) => Product(
        id: _i(j, 'id'), name: _s(j, 'name'), price: _d(j, 'price'), oldPrice: _d(j, 'oldPrice'),
        category: _s(j, 'category'), desc: _s(j, 'desc'), imageUrl: _s(j, 'imageUrl'), mediaType: _s(j, 'mediaType').isEmpty ? 'image' : _s(j, 'mediaType'), publicId: _s(j, 'publicId'), extUrl: _s(j, 'extUrl'),
        stock: _i(j, 'stock'), colorValue: _i(j, 'colorValue') == 0 ? 0xFF42A5F5 : _i(j, 'colorValue'),
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'price': price, 'oldPrice': oldPrice, 'category': category, 'desc': desc,
        'imageUrl': imageUrl, 'mediaType': mediaType, 'publicId': publicId, 'extUrl': extUrl, 'stock': stock, 'colorValue': colorValue,
      };
}

class AppUser {
  int id;
  String name, email, phone, password, address, membership;
  bool isAdmin, blocked;
  // password শুধু Admin নতুন পাসওয়ার্ড দিলে ভরা থাকে। database থেকে পাসওয়ার্ড কখনো আসে না।
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.password = '',
    this.address = '',
    this.membership = 'None',
    this.isAdmin = false,
    this.blocked = false,
  });
  factory AppUser.fromJson(Map j) => AppUser(
        id: _i(j, 'id'), name: _s(j, 'name'), email: _s(j, 'email'), phone: _s(j, 'phone'),
        address: _s(j, 'address'), membership: _s(j, 'membership').isEmpty ? 'None' : _s(j, 'membership'),
        isAdmin: _b(j, 'isAdmin'), blocked: _b(j, 'blocked'),
      );
  Map<String, dynamic> toAdminJson() => {
        'id': id, 'name': name, 'email': email, 'phone': phone, 'address': address, 'membership': membership,
        'isAdmin': isAdmin, 'blocked': blocked,
        if (password.isNotEmpty) 'password': password,
      };
}

class CartItem {
  Product product;
  int qty;
  CartItem(this.product, this.qty);
}

// অর্ডারের ভেতরের একটা লাইন (পণ্য পরে delete হলেও নাম/দাম থেকে যায়)
class OrderItem {
  int productId, qty;
  String name;
  double price;
  OrderItem({required this.productId, required this.name, required this.price, required this.qty});
  factory OrderItem.fromJson(Map j) => OrderItem(productId: _i(j, 'productId'), name: _s(j, 'name'), price: _d(j, 'price'), qty: _i(j, 'qty'));
}

class Order {
  int id;
  String userEmail, userName, phone, address, payment, trxId, status, date;
  List<OrderItem> items;
  double total;
  bool returnRequested;
  String returnReason;
  Order({
    required this.id,
    required this.userEmail,
    required this.userName,
    required this.phone,
    required this.address,
    required this.payment,
    this.trxId = '',
    this.status = 'Pending',
    required this.date,
    required this.items,
    required this.total,
    this.returnRequested = false,
    this.returnReason = '',
  });
  factory Order.fromJson(Map j) => Order(
        id: _i(j, 'id'), userEmail: _s(j, 'userEmail'), userName: _s(j, 'userName'), phone: _s(j, 'phone'),
        address: _s(j, 'address'), payment: _s(j, 'payment'), trxId: _s(j, 'trxId'), status: _s(j, 'status'),
        date: _s(j, 'date'), total: _d(j, 'total'), returnRequested: _b(j, 'returnRequested'),
        returnReason: _s(j, 'returnReason'),
        items: [for (final i in (j['items'] as List? ?? [])) OrderItem.fromJson(i as Map)],
      );
}

class Review {
  int id, productId, rating;
  String userName, comment;
  bool approved;
  Review({required this.id, required this.productId, required this.rating, required this.userName, required this.comment, this.approved = false});
  factory Review.fromJson(Map j) => Review(
        id: _i(j, 'id'), productId: _i(j, 'productId'), rating: _i(j, 'rating'),
        userName: _s(j, 'userName'), comment: _s(j, 'comment'), approved: _b(j, 'approved'),
      );
  Map<String, dynamic> toJson() => {'id': id, 'approved': approved};
}

class HeroSlide {
  int id;
  String title, subtitle, buttonText, imageUrl, mediaType, publicId, category;
  int colorValue;
  HeroSlide({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.buttonText = 'Shop Now',
    this.imageUrl = '',
    this.mediaType = 'image',
    this.publicId = '',
    this.category = 'All',
    this.colorValue = 0xFF1E88E5,
  });
   factory HeroSlide.fromJson(Map j) => HeroSlide(
        id: _i(j, 'id'), title: _s(j, 'title'), subtitle: _s(j, 'subtitle'), buttonText: _s(j, 'buttonText'),
        imageUrl: _s(j, 'imageUrl'), mediaType: _s(j, 'mediaType').isEmpty ? 'image' : _s(j, 'mediaType'), publicId: _s(j, 'publicId'), category: _s(j, 'category'),
        colorValue: _i(j, 'colorValue') == 0 ? 0xFF1E88E5 : _i(j, 'colorValue'),
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'subtitle': subtitle, 'buttonText': buttonText, 'imageUrl': imageUrl,
        'mediaType': mediaType, 'publicId': publicId, 'category': category, 'colorValue': colorValue,
      };
}

class Membership {
  int id;
  String name, perks;
  double price;
  int discount; // শতাংশ
  Membership({required this.id, required this.name, required this.price, required this.discount, required this.perks});
  factory Membership.fromJson(Map j) => Membership(id: _i(j, 'id'), name: _s(j, 'name'), price: _d(j, 'price'), discount: _i(j, 'discount'), perks: _s(j, 'perks'));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price, 'discount': discount, 'perks': perks};
}

class LinkItem {
  String label, url;
  LinkItem(this.label, this.url);
  factory LinkItem.fromJson(Map j) => LinkItem(_s(j, 'label'), _s(j, 'url'));
  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

// ============================================================================
// 2. API  (server.js এর সাথে কথা বলা)
// ============================================================================

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

http.MediaType _guessMediaType(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  const map = <String, String>{
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
    'webp': 'image/webp', 'bmp': 'image/bmp', 'svg': 'image/svg+xml',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'mkv': 'video/x-matroska', 'avi': 'video/x-msvideo',
  };
  final mt = map[ext];
  if (mt != null) return http.MediaType.parse(mt);
  return http.MediaType('application', 'octet-stream');
}

class Api {
  static String? token; // লগইনের পর server যে চাবি দেয়, সেটা এখানে থাকে

  // method: GET / POST / PUT / DELETE   path: যেমন '/api/data'
  static Future<dynamic> call(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    late http.Response r;
    try {
      if (method == 'GET') {
        r = await http.get(uri, headers: headers);
      } else if (method == 'POST') {
        r = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      } else if (method == 'PUT') {
        r = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
      } else {
        r = await http.delete(uri, headers: headers);
      }
    } catch (e) {
      throw ApiError('Cannot reach the server at $apiBaseUrl. Is "node server.js" running?');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 400) {
      if (r.statusCode == 401 && token != null) store.sessionExpired();
      throw ApiError(data is Map && data['error'] != null ? '${data['error']}' : 'Server error (${r.statusCode})');
    }
    return data;
  }

  // Admin-only: upload an image/video file to Cloudinary via backend.
  // Returns the parsed JSON (contains secure_url, public_id, resource_type, ...).
  static Future<dynamic> uploadFile(Uint8List bytes, String filename) async {
    final uri = Uri.parse('$apiBaseUrl/api/admin/upload');
    final req = http.MultipartRequest('POST', uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _guessMediaType(filename)));
    late http.StreamedResponse streamed;
    try {
      streamed = await req.send();
    } catch (e) {
      throw ApiError('Cannot reach the server at $apiBaseUrl. Is "node server.js" running?');
    }
    final r = await http.Response.fromStream(streamed);
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 400) {
      if (r.statusCode == 401 && token != null) store.sessionExpired();
      throw ApiError(data is Map && data['error'] != null ? '${data['error']}' : 'Server error (${r.statusCode})');
    }
    return data;
  }
}

// ============================================================================
// 3. STORE  (অ্যাপের ডাটা)
// ============================================================================

const orderStatuses = ['Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled', 'Returned'];

const palette = <String, int>{
  'Blue': 0xFF1E88E5,
  'Green': 0xFF43A047,
  'Red': 0xFFE53935,
  'Orange': 0xFFFB8C00,
  'Purple': 0xFF8E24AA,
  'Teal': 0xFF00897B,
  'Pink': 0xFFD81B60,
  'Brown': 0xFF6D4C41,
};

String colorName(int v) =>
    palette.entries.firstWhere((e) => e.value == v, orElse: () => palette.entries.first).key;

class Store extends ChangeNotifier {
  // ---- Site Branding (database এর settings থেকে আসে) ----
  String siteName = 'MyShop';
  String logoText = '🛍️';
  String logoUrl = '';
  String tagline = '';
  String announcement = '';
  bool showAnnouncement = true;
  String footerText = '';
  String currency = '৳';
  String siteUrl = 'https://myshop.example.com';
  int primaryColor = 0xFF1E88E5;
  String whatsapp = '';
  String bkashNumber = '';
  String contactEmail = '';
  String contactPhone = '';
  String contactAddress = '';
  int perPage = 6;
  double deliveryFee = 60;

  // ---- ডাটা ----
  List<LinkItem> links = [];
  List<String> categories = [];
  List<Product> products = [];
  List<AppUser> users = []; // শুধু Admin এর জন্য
  List<Order> orders = []; // Admin: সব অর্ডার, Customer: নিজের অর্ডার
  List<Review> reviews = [];
  List<HeroSlide> slides = [];
  List<Membership> memberships = [];

  // ---- অবস্থা ----
  String loadState = 'loading'; // loading / ready / error
  String loadError = '';
  String syncStatus = ''; // Admin এর save অবস্থা
  bool syncError = false;
  bool saving = false;

  // ---- Session ----
  AppUser? currentUser;
  List<CartItem> cart = [];
  Order? lastOrder;

  int _lastId = 0;
  int nextId() {
    final t = DateTime.now().millisecondsSinceEpoch * 10;
    _lastId = t > _lastId ? t : _lastId + 1;
    return _lastId;
  }

  // ------------------------------------------------------------------
  //  database থেকে ডাটা আনা
  // ------------------------------------------------------------------
  void _applySettings(Map s) {
    siteName = _s(s, 'siteName');
    logoText = _s(s, 'logoText');
    logoUrl = _s(s, 'logoUrl');
    tagline = _s(s, 'tagline');
    announcement = _s(s, 'announcement');
    showAnnouncement = _b(s, 'showAnnouncement');
    footerText = _s(s, 'footerText');
    currency = _s(s, 'currency');
    siteUrl = _s(s, 'siteUrl');
    primaryColor = _i(s, 'primaryColor') == 0 ? 0xFF1E88E5 : _i(s, 'primaryColor');
    whatsapp = _s(s, 'whatsapp');
    bkashNumber = _s(s, 'bkashNumber');
    contactEmail = _s(s, 'contactEmail');
    contactPhone = _s(s, 'contactPhone');
    contactAddress = _s(s, 'contactAddress');
    perPage = _i(s, 'perPage') < 1 ? 6 : _i(s, 'perPage');
    deliveryFee = _d(s, 'deliveryFee');
    categories = [for (final c in (s['categories'] as List? ?? [])) c.toString()];
    links = [for (final l in (s['links'] as List? ?? [])) LinkItem.fromJson(l as Map)];
  }

  Future<void> _fetchPublic() async {
    final d = await Api.call('GET', '/api/data');
    _applySettings(d['settings'] as Map);
    products = [for (final p in d['products'] as List) Product.fromJson(p as Map)];
    slides = [for (final s in d['slides'] as List) HeroSlide.fromJson(s as Map)];
    memberships = [for (final m in d['memberships'] as List) Membership.fromJson(m as Map)];
    reviews = [for (final r in d['reviews'] as List) Review.fromJson(r as Map)];
  }

  Future<void> loadPublic({bool silent = false}) async {
    if (!silent) {
      loadState = 'loading';
      notifyListeners();
    }
    try {
      await _fetchPublic();
      loadState = 'ready';
    } catch (e) {
      if (!silent) {
        loadState = 'error';
        loadError = e.toString();
      }
    }
    notifyListeners();
  }

  Future<void> loadAdmin() async {
    if (adminLoaded) {
      _timer?.cancel();
      await flush(); // আগে অসমাপ্ত save শেষ করা
    }
    try {
      await _fetchPublic();
      final d = await Api.call('GET', '/api/admin/data');
      users = [for (final u in d['users'] as List) AppUser.fromJson(u as Map)];
      orders = [for (final o in d['orders'] as List) Order.fromJson(o as Map)];
      reviews = [for (final r in d['reviews'] as List) Review.fromJson(r as Map)];
      adminLoaded = true;
      _snap = _currentSnap();
      syncError = false;
      syncStatus = 'All changes saved ✓';
    } catch (e) {
      syncError = true;
      syncStatus = 'Could not load admin data: $e';
    }
    notifyListeners();
  }

  Future<void> loadMyOrders() async {
    try {
      final d = await Api.call('GET', '/api/my/orders');
      orders = [for (final o in d as List) Order.fromJson(o as Map)];
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  //  Auth
  // ------------------------------------------------------------------
  Future<void> _afterLogin(dynamic d) async {
    Api.token = d['token'] as String;
    currentUser = AppUser.fromJson(d['user'] as Map);
    adminLoaded = false;
    users = [];
    orders = [];
    if (currentUser!.isAdmin) {
      await loadAdmin();
    } else {
      await loadMyOrders();
    }
    notifyListeners();
  }

  Future<String?> register(String name, String email, String phone, String pass) async {
    try {
      final d = await Api.call('POST', '/api/register', {'name': name, 'email': email, 'phone': phone, 'password': pass});
      await _afterLogin(d);
      return null; // null মানে সফল
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String?> login(String email, String pass, {bool adminOnly = false}) async {
    try {
      final d = await Api.call('POST', '/api/login', {'email': email, 'password': pass, 'adminOnly': adminOnly});
      await _afterLogin(d);
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    _timer?.cancel();
    if (adminLoaded) await flush(); // বের হওয়ার আগে সব save করে নেওয়া
    _clearSession();
    notifyListeners();
    loadPublic(silent: true); // approved নয় এমন review ইত্যাদি মুছে সাধারণ ডাটা আবার আনা
  }

  void _clearSession() {
    Api.token = null;
    currentUser = null;
    cart.clear();
    users = [];
    orders = [];
    adminLoaded = false;
    _snap = {};
    syncStatus = '';
    syncError = false;
    saving = false;
  }

  void sessionExpired() {
    if (currentUser == null) return;
    adminLoaded = false;
    _timer?.cancel();
    _clearSession();
    notifyListeners();
    loadPublic(silent: true);
  }

  // ------------------------------------------------------------------
  //  Cart
  // ------------------------------------------------------------------
  int get cartCount => cart.fold(0, (s, i) => s + i.qty);
  double get subtotal => cart.fold(0.0, (s, i) => s + i.product.price * i.qty);
  int get discountPercent {
    final u = currentUser;
    if (u == null) return 0;
    final m = memberships.where((m) => m.name == u.membership);
    return m.isEmpty ? 0 : m.first.discount;
  }

  double get discountAmount => subtotal * discountPercent / 100;
  double get total => cart.isEmpty ? 0 : subtotal - discountAmount + deliveryFee;

  bool addToCart(Product p, [int qty = 1]) {
    final idx = cart.indexWhere((c) => c.product.id == p.id);
    final have = idx >= 0 ? cart[idx].qty : 0;
    if (have + qty > p.stock) return false;
    if (idx >= 0) {
      cart[idx].qty += qty;
    } else {
      cart.add(CartItem(p, qty));
    }
    notifyListeners();
    return true;
  }

  void changeQty(CartItem c, int delta) {
    final n = c.qty + delta;
    if (n <= 0) {
      cart.remove(c);
    } else if (n <= c.product.stock) {
      c.qty = n;
    }
    notifyListeners();
  }

  void removeFromCart(CartItem c) {
    cart.remove(c);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  //  Customer actions (database এ সরাসরি যায়)
  // ------------------------------------------------------------------
  Future<String?> placeOrder({required String name, required String phone, required String address, required String payment, String trxId = ''}) async {
    try {
      final d = await Api.call('POST', '/api/orders', {
        'name': name, 'phone': phone, 'address': address, 'payment': payment, 'trxId': trxId,
        'items': [for (final c in cart) {'productId': c.product.id, 'qty': c.qty}],
      });
      final o = Order.fromJson(d as Map);
      for (final c in cart) {
        c.product.stock -= c.qty;
      }
      orders.insert(0, o);
      lastOrder = o;
      cart.clear();
      notifyListeners();
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String?> saveProfile(String name, String phone, String address, String newPass) async {
    try {
      final d = await Api.call('PUT', '/api/me', {'name': name, 'phone': phone, 'address': address, 'password': newPass});
      currentUser = AppUser.fromJson(d as Map);
      notifyListeners();
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String?> joinMembership(String planName) async {
    try {
      final d = await Api.call('POST', '/api/me/membership', {'name': planName});
      currentUser = AppUser.fromJson(d as Map);
      notifyListeners();
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String?> requestReturn(Order o, String reason) async {
    try {
      await Api.call('POST', '/api/orders/${o.id}/return', {'reason': reason});
      o.returnRequested = true;
      o.returnReason = reason;
      notifyListeners();
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String?> submitReview(int productId, int rating, String comment) async {
    try {
      await Api.call('POST', '/api/reviews', {'productId': productId, 'rating': rating, 'comment': comment});
      return null;
    } on ApiError catch (e) {
      return e.message;
    }
  }

  // ------------------------------------------------------------------
  //  Admin: অর্ডারের status বদলানো (বাতিল/রিটার্ন হলে stock ফেরত যায়)
  // ------------------------------------------------------------------
  bool _inactive(String s) => s == 'Cancelled' || s == 'Returned';

  void setStatus(Order o, String s) {
    final delta = (!_inactive(o.status) && _inactive(s)) ? 1 : ((_inactive(o.status) && !_inactive(s)) ? -1 : 0);
    if (delta != 0) {
      for (final i in o.items) {
        final idx = products.indexWhere((p) => p.id == i.productId);
        if (idx >= 0) products[idx].stock += delta * i.qty;
      }
    }
    o.status = s;
    update();
  }

  double avgRating(int pid) {
    final r = reviews.where((r) => r.productId == pid && r.approved).toList();
    if (r.isEmpty) return 0;
    return r.fold(0, (s, x) => s + x.rating) / r.length;
  }

  int reviewCount(int pid) => reviews.where((r) => r.productId == pid && r.approved).length;

  // ------------------------------------------------------------------
  //  Admin: AUTO-SAVE
  //  Admin Panel যেকোনো কিছু বদলে store.update() ডাকে।
  //  তখন আমরা আগের অবস্থার সাথে তুলনা করে শুধু বদলানো অংশ database এ পাঠাই।
  // ------------------------------------------------------------------
  bool adminLoaded = false;
  Map<String, String> _snap = {}; // শেষবার save করা অবস্থার ছবি
  Timer? _timer;
  bool _flushing = false;
  bool _again = false;

  void update() {
    _schedule();
    notifyListeners();
  }

  void _schedule() {
    if (currentUser?.isAdmin != true || !adminLoaded) return;
    saving = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), flush); // ০.৭ সেকেন্ড থামলে save
  }

  Map<String, String> _currentSnap() {
    final m = <String, String>{};
    for (final p in products) {
      m['products:${p.id}'] = jsonEncode(p.toJson());
    }
    for (final s in slides) {
      m['slides:${s.id}'] = jsonEncode(s.toJson());
    }
    for (final x in memberships) {
      m['memberships:${x.id}'] = jsonEncode(x.toJson());
    }
    for (final u in users) {
      m['users:${u.id}'] = jsonEncode(u.toAdminJson());
    }
    for (final r in reviews) {
      m['reviews:${r.id}'] = jsonEncode(r.toJson());
    }
    for (final o in orders) {
      m['orders:${o.id}'] = jsonEncode({'id': o.id, 'status': o.status});
    }
    m['settings:main'] = jsonEncode(settingsJson());
    return m;
  }

  Map<String, dynamic> settingsJson() => {
        'siteName': siteName, 'logoText': logoText, 'logoUrl': logoUrl, 'tagline': tagline,
        'announcement': announcement, 'showAnnouncement': showAnnouncement, 'footerText': footerText,
        'currency': currency, 'siteUrl': siteUrl, 'primaryColor': primaryColor, 'whatsapp': whatsapp,
        'bkashNumber': bkashNumber, 'contactEmail': contactEmail, 'contactPhone': contactPhone,
        'contactAddress': contactAddress, 'perPage': perPage, 'deliveryFee': deliveryFee,
        'categories': categories, 'links': links.map((l) => l.toJson()).toList(),
      };

  Future<void> flush() async {
    if (!adminLoaded) return;
    if (_flushing) {
      _again = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _again = false;
        final now = _currentSnap();
        for (final col in ['products', 'slides', 'memberships', 'users', 'reviews', 'orders']) {
          final up = <dynamic>[];
          final del = <int>[];
          now.forEach((k, v) {
            if (k.startsWith('$col:') && _snap[k] != v) up.add(jsonDecode(v)); // নতুন বা বদলানো
          });
          for (final k in _snap.keys) {
            if (k.startsWith('$col:') && !now.containsKey(k)) del.add(int.parse(k.substring(col.length + 1))); // মুছে ফেলা
          }
          if (up.isNotEmpty) await Api.call('POST', '/api/admin/$col/upsert', {'items': up});
          if (del.isNotEmpty) await Api.call('POST', '/api/admin/$col/delete', {'ids': del});
        }
        if (_snap['settings:main'] != now['settings:main']) {
          await Api.call('PUT', '/api/admin/settings', jsonDecode(now['settings:main']!));
        }
        // নতুন পাসওয়ার্ড পাঠানো হয়ে গেলে অ্যাপের মেমোরি থেকে মুছে ফেলা
        for (final u in users) {
          final k = 'users:${u.id}';
          if (u.password.isNotEmpty && now[k] == jsonEncode(u.toAdminJson())) {
            u.password = '';
            now[k] = jsonEncode(u.toAdminJson());
          }
        }
        _snap = now;
        syncError = false;
        syncStatus = 'All changes saved ✓';
      } while (_again);
    } on ApiError catch (e) {
      syncError = true;
      syncStatus = 'Save failed: ${e.message}';
    } catch (e) {
      syncError = true;
      syncStatus = 'Save failed: $e';
    }
    _flushing = false;
    saving = false;
    notifyListeners();
  }
}

final store = Store(); // পুরো অ্যাপে একটাই Store

// ============================================================================
// 4. HELPERS
// ============================================================================

String money(num v) => '${store.currency}${v.toStringAsFixed(0)}';

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}

// Store বদলালে নিচের Widget নিজে নিজে আবার আঁকা হয়
Widget watch(Widget Function() build) => ListenableBuilder(listenable: store, builder: (_, __) => build());

// বড় স্ক্রিনে কনটেন্ট মাঝখানে রাখে
Widget box(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: child));

Color statusColor(String s) {
  switch (s) {
    case 'Pending':
      return Colors.orange;
    case 'Processing':
      return Colors.blue;
    case 'Shipped':
      return Colors.purple;
    case 'Delivered':
      return Colors.green;
    case 'Cancelled':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

Widget productImage(Product p) {
  final fallback = Container(
    color: Color(p.colorValue).withOpacity(0.25),
    alignment: Alignment.center,
    child: Icon(Icons.shopping_bag, size: 48, color: Color(p.colorValue)),
  );
  if (p.imageUrl.isEmpty) return fallback;
  if (p.mediaType == 'video') {
    return Container(
      color: Color(p.colorValue).withOpacity(0.25),
      alignment: Alignment.center,
      child: Icon(Icons.play_circle_fill, size: 48, color: Color(p.colorValue)),
    );
  }
  return Image.network(p.imageUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => fallback);
}

Widget logoWidget({double size = 30}) {
  final fallback = Text(store.logoText, style: TextStyle(fontSize: size * 0.8));
  if (store.logoUrl.isEmpty) return fallback;
  return Image.network(store.logoUrl, height: size, errorBuilder: (_, __, ___) => fallback);
}

Widget cartButton(BuildContext context) => IconButton(
      tooltip: 'Cart',
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage())),
      icon: Badge(
        isLabelVisible: store.cartCount > 0,
        label: Text('${store.cartCount}'),
        child: const Icon(Icons.shopping_cart_outlined),
      ),
    );

String productLink(Product p) => '${store.siteUrl}/product/${p.id}';

void addAndNotify(BuildContext c, Product p, [int q = 1]) {
  if (p.stock <= 0) return snack(c, 'Sorry, out of stock');
  snack(c, store.addToCart(p, q) ? 'Added to cart ✅' : 'Not enough stock');
}

// Buy button: কার্টে যোগ করে সরাসরি Checkout এ যায়
Future<void> buyNow(BuildContext context, Product p) async {
  if (p.stock <= 0) return snack(context, 'Sorry, out of stock');
  if (!store.addToCart(p)) return snack(context, 'Not enough stock');
  await goCheckout(context);
}

Future<void> goCheckout(BuildContext context) async {
  if (store.currentUser == null) {
    snack(context, 'Please login first');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    if (store.currentUser == null || !context.mounted) return;
  }
  if (store.cart.isEmpty) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage()));
}

Future<bool> confirm(BuildContext context, String msg) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you sure?'),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
      ],
    ),
  );
  return r ?? false;
}

// সাধারণ ফর্ম ডায়ালগ: fields = {'লেবেল': 'শুরুর মান'} ফেরত দেয় {'লেবেল': 'নতুন মান'}
Future<Map<String, String>?> formDialog(
  BuildContext context,
  String title,
  Map<String, String> fields, {
  Map<String, List<String>> dropdowns = const {},
  Set<String> multiline = const {},
}) {
  final ctrls = {for (final e in fields.entries) e.key: TextEditingController(text: e.value)};
  final dd = {
    for (final k in dropdowns.keys) k: dropdowns[k]!.contains(fields[k]) ? fields[k]! : dropdowns[k]!.first,
  };
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in fields.keys)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: dropdowns.containsKey(k)
                        ? DropdownButtonFormField<String>(
                            value: dd[k],
                            decoration: InputDecoration(labelText: k, border: const OutlineInputBorder()),
                            items: [for (final o in dropdowns[k]!) DropdownMenuItem(value: o, child: Text(o))],
                            onChanged: (v) => setS(() => dd[k] = v!),
                          )
                        : TextField(
                            controller: ctrls[k],
                            maxLines: multiline.contains(k) ? 3 : 1,
                            decoration: InputDecoration(labelText: k, border: const OutlineInputBorder()),
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final r = <String, String>{};
              for (final k in fields.keys) {
                r[k] = dropdowns.containsKey(k) ? dd[k]! : ctrls[k]!.text.trim();
              }
              Navigator.pop(ctx, r);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

// ---- WhatsApp Message / Share ----
// share=false -> আপনার WhatsApp নাম্বারে মেসেজ, share=true -> যে কাউকে শেয়ার
void showWhatsAppDialog(BuildContext context, {String preset = 'Hello! I want to know about your products.', bool share = false}) {
  final ctrl = TextEditingController(text: preset);
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final base = share ? 'https://wa.me/' : 'https://wa.me/${store.whatsapp}';
        final link = '$base?text=${Uri.encodeComponent(ctrl.text)}';
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.chat, color: Color(0xFF25D366)),
            const SizedBox(width: 8),
            Flexible(child: Text(share ? 'Share on WhatsApp' : 'Message us on WhatsApp')),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: ctrl,
                maxLines: 4,
                onChanged: (_) => setS(() {}),
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Your message'),
              ),
              const SizedBox(height: 12),
              const Text('Link:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(link, style: const TextStyle(fontSize: 12, color: Colors.blue)),
              const SizedBox(height: 8),
              const Text(
                'To open WhatsApp directly, add the url_launcher package: launchUrl(Uri.parse(link)).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(ctx);
                snack(context, 'Link copied ✅');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy link'),
            ),
          ],
        );
      },
    ),
  );
}

// ---- Third-party link button ----
void openLink(BuildContext context, String label, String url) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(url, style: const TextStyle(color: Colors.blue)),
        const SizedBox(height: 8),
        const Text('To open links in the browser, add the url_launcher package.', style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        FilledButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(ctx);
            snack(context, 'Link copied ✅');
          },
          child: const Text('Copy'),
        ),
      ],
    ),
  );
}

Widget qtyStepper(int qty, VoidCallback minus, VoidCallback plus) => Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(visualDensity: VisualDensity.compact, onPressed: minus, icon: const Icon(Icons.remove_circle_outline)),
      Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      IconButton(visualDensity: VisualDensity.compact, onPressed: plus, icon: const Icon(Icons.add_circle_outline)),
    ]);

Widget stars(double v, {double size = 16}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(v >= i ? Icons.star : (v >= i - 0.5 ? Icons.star_half : Icons.star_border), size: size, color: Colors.amber),
      ],
    );

// ============================================================================
// 5. FRONTEND
// ============================================================================

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});
  @override
  Widget build(BuildContext context) => watch(() => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: store.siteName,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Color(store.primaryColor)),
        // ডাটা লোড না হওয়া পর্যন্ত StartupPage দেখায়
        home: store.loadState == 'ready' ? const HomePage() : const StartupPage(),
      ));
}

// ------------------------------ STARTUP -------------------------------------
class StartupPage extends StatelessWidget {
  const StartupPage({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: store.loadState == 'loading'
                  ? const Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading shop...'),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 64, color: Colors.red),
                      const SizedBox(height: 12),
                      const Text('Cannot load the shop', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(store.loadError, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      const Text(
                        'Checklist:\n1. server.js is running (node server.js)\n2. MongoDB key is set inside server.js\n3. apiBaseUrl at the top of main.dart is correct',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(onPressed: () => store.loadPublic(), icon: const Icon(Icons.refresh), label: const Text('Retry')),
                    ]),
            ),
          ),
        ));
  }
}

// ------------------------------ HOME PAGE -----------------------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String category = 'All';
  String query = '';
  int page = 1;

  List<Product> get filtered => store.products
      .where((p) => (category == 'All' || p.category == category) && p.name.toLowerCase().contains(query.toLowerCase()))
      .toList();

  void setCategory(String c) => setState(() {
        category = c;
        page = 1;
      });

  @override
  Widget build(BuildContext context) {
    return watch(() {
      final list = filtered;
      var pages = (list.length / store.perPage).ceil();
      if (pages < 1) pages = 1;
      if (page > pages) page = pages;
      final shown = list.skip((page - 1) * store.perPage).take(store.perPage).toList();
      final user = store.currentUser;

      return Scaffold(
        appBar: AppBar(
          title: Row(children: [
            logoWidget(),
            const SizedBox(width: 8),
            Flexible(child: Text(store.siteName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          actions: [
            if (user?.isAdmin == true)
              IconButton(
                tooltip: 'Admin Panel',
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())),
              ),
            IconButton(
              tooltip: user == null ? 'Login' : 'Profile',
              icon: Icon(user == null ? Icons.login : Icons.person),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => user == null ? const LoginPage() : const ProfilePage()),
              ),
            ),
            cartButton(context),
          ],
        ),
        drawer: _buildDrawer(context),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          tooltip: 'WhatsApp message',
          onPressed: () => showWhatsAppDialog(context),
          child: const Icon(Icons.chat),
        ),
        body: ListView(children: [
          if (store.showAnnouncement && store.announcement.isNotEmpty)
            Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.all(8),
              child: Text(store.announcement, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          box(Padding(padding: const EdgeInsets.all(12), child: HeroSlider(onCategory: setCategory))),
          box(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              onChanged: (v) => setState(() {
                query = v;
                page = 1;
              }),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products...', border: OutlineInputBorder()),
            ),
          )),
          box(SizedBox(
            height: 56,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(12), children: [
              for (final c in ['All', ...store.categories])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setCategory(c)),
                ),
            ]),
          )),
          box(Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text('$category  (${list.length} products)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          )),
          if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No products found')))
          else
            box(GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 330,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: shown.length,
              itemBuilder: (_, i) => ProductCard(shown[i]),
            )),
          // ---- Pagination (Prev / Page numbers / Next) ----
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              OutlinedButton.icon(
                onPressed: page > 1 ? () => setState(() => page--) : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Prev'),
              ),
              for (var i = 1; i <= pages; i++)
                i == page
                    ? FilledButton(onPressed: () {}, child: Text('$i'))
                    : OutlinedButton(onPressed: () => setState(() => page = i), child: Text('$i')),
              OutlinedButton(
                onPressed: page < pages ? () => setState(() => page++) : null,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Next'), Icon(Icons.chevron_right)]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          const Footer(),
        ]),
      );
    });
  }

  // Categories Drawer
  Widget _buildDrawer(BuildContext context) {
    final user = store.currentUser;
    void go(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    return Drawer(
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            logoWidget(size: 48),
            const SizedBox(height: 8),
            Text(store.siteName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(store.tagline, style: const TextStyle(fontSize: 12)),
          ]),
        ),
        ListTile(
          leading: const Icon(Icons.apps),
          title: const Text('All Products'),
          selected: category == 'All',
          onTap: () {
            Navigator.pop(context);
            setCategory('All');
          },
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('CATEGORIES', style: TextStyle(color: Colors.grey, fontSize: 12))),
        for (final c in store.categories)
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(c),
            trailing: Text('${store.products.where((p) => p.category == c).length}'),
            selected: category == c,
            onTap: () {
              Navigator.pop(context);
              setCategory(c);
            },
          ),
        const Divider(),
        for (final l in store.links)
          ListTile(leading: const Icon(Icons.link), title: Text(l.label), onTap: () => openLink(context, l.label, l.url)),
        const Divider(),
        if (user == null) ...[
          ListTile(leading: const Icon(Icons.login), title: const Text('Login'), onTap: () => go(const LoginPage())),
          ListTile(leading: const Icon(Icons.person_add), title: const Text('Register'), onTap: () => go(const RegisterPage())),
        ] else ...[
          ListTile(leading: const Icon(Icons.person), title: const Text('My Profile'), onTap: () => go(const ProfilePage())),
          if (user.isAdmin)
            ListTile(leading: const Icon(Icons.admin_panel_settings), title: const Text('Admin Panel'), onTap: () => go(const AdminPage())),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              store.logout();
              snack(context, 'Logged out');
            },
          ),
        ],
      ]),
    );
  }
}

// ------------------------------ HERO SLIDER ---------------------------------
class HeroSlider extends StatefulWidget {
  final void Function(String category) onCategory;
  const HeroSlider({super.key, required this.onCategory});
  @override
  State<HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<HeroSlider> {
  final pc = PageController();
  int idx = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // প্রতি ৪ সেকেন্ডে নিজে নিজে স্লাইড বদলায়
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final n = store.slides.length;
      if (n < 2 || !pc.hasClients) return;
      pc.animateToPage((idx + 1) % n, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    pc.dispose();
    super.dispose();
  }

  void go(int i) => pc.animateToPage(i, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);

  Widget slide(HeroSlide s) => Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(s.colorValue), Color(s.colorValue).withOpacity(0.6)])),
        child: Stack(fit: StackFit.expand, children: [
           if (s.imageUrl.isNotEmpty && s.mediaType != 'video') Image.network(s.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          Container(color: Colors.black26),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 20),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(s.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => widget.onCategory(s.category),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black87),
                child: Text(s.buttonText),
              ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return watch(() {
      final n = store.slides.length;
      if (n == 0) return const SizedBox.shrink();
      final cur = idx >= n ? 0 : idx;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 220,
          child: Stack(children: [
            PageView.builder(
              controller: pc,
              itemCount: n,
              onPageChanged: (i) => setState(() => idx = i),
              itemBuilder: (_, i) => slide(store.slides[i]),
            ),
            if (n > 1) ...[
              Positioned(
                left: 4, top: 0, bottom: 0,
                child: Center(child: IconButton(color: Colors.white, onPressed: () => go((cur - 1 + n) % n), icon: const Icon(Icons.chevron_left, size: 32))),
              ),
              Positioned(
                right: 4, top: 0, bottom: 0,
                child: Center(child: IconButton(color: Colors.white, onPressed: () => go((cur + 1) % n), icon: const Icon(Icons.chevron_right, size: 32))),
              ),
            ],
            Positioned(
              bottom: 8, left: 0, right: 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < n; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == cur ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(color: i == cur ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(4)),
                  ),
              ]),
            ),
          ]),
        ),
      );
    });
  }
}

// ----------------------------- PRODUCT CARD ---------------------------------
class ProductCard extends StatelessWidget {
  final Product p;
  const ProductCard(this.p, {super.key});

  @override
  Widget build(BuildContext context) {
    final discount = p.oldPrice > p.price ? ((p.oldPrice - p.price) / p.oldPrice * 100).round() : 0;
    final rating = store.avgRating(p.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductPage(p))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              productImage(p),
              if (discount > 0)
                Positioned(
                  top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    child: Text('-$discount%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              if (p.stock <= 0)
                Container(color: Colors.black45, alignment: Alignment.center, child: const Text('SOLD OUT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(children: [
                Text(money(p.price), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                if (p.oldPrice > p.price) ...[
                  const SizedBox(width: 6),
                  Text(money(p.oldPrice), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 12)),
                ],
              ]),
              const SizedBox(height: 2),
              Row(children: [
                stars(rating, size: 14),
                Text(' (${store.reviewCount(p.id)})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => addAndNotify(context, p),
                    child: const Icon(Icons.add_shopping_cart, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => buyNow(context, p),
                    child: const Text('Buy'),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ----------------------------- PRODUCT PAGE ---------------------------------
class ProductPage extends StatefulWidget {
  final Product p;
  const ProductPage(this.p, {super.key});
  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  int qty = 1;
  int rating = 5;
  final comment = TextEditingController();

  Future<void> submitReview() async {
    final p = widget.p;
    if (store.currentUser == null) return snack(context, 'Please login to write a review');
    if (comment.text.trim().isEmpty) return snack(context, 'Write a comment first');
    final err = await store.submitReview(p.id, rating, comment.text.trim());
    if (!mounted) return;
    if (err != null) return snack(context, err);
    comment.clear();
    snack(context, 'Thanks! Your review will show after admin approval.');
  }

  @override
  Widget build(BuildContext context) {
    return watch(() {
      final p = widget.p;
      final revs = store.reviews.where((r) => r.productId == p.id && r.approved).toList();
      final image = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(height: 320, width: double.infinity, child: productImage(p)),
      );
      final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Chip(label: Text(p.category)),
        Text(p.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(children: [stars(store.avgRating(p.id), size: 20), Text('  ${store.reviewCount(p.id)} reviews')]),
        const SizedBox(height: 10),
        Row(children: [
          Text(money(p.price), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          if (p.oldPrice > p.price) ...[
            const SizedBox(width: 10),
            Text(money(p.oldPrice), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 18)),
          ],
        ]),
        const SizedBox(height: 6),
        Text(p.stock > 0 ? 'In stock: ${p.stock}' : 'Out of stock', style: TextStyle(color: p.stock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(p.desc),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Quantity: '),
          qtyStepper(qty, () => setState(() => qty = qty > 1 ? qty - 1 : 1), () => setState(() => qty = qty < p.stock ? qty + 1 : qty)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: () => addAndNotify(context, p, qty), icon: const Icon(Icons.add_shopping_cart), label: const Text('Add to Cart')),
          FilledButton.icon(
            onPressed: () async {
              if (p.stock <= 0) return snack(context, 'Sorry, out of stock');
              if (!store.addToCart(p, qty)) return snack(context, 'Not enough stock');
              await goCheckout(context);
            },
            icon: const Icon(Icons.flash_on),
            label: const Text('Buy Now'),
          ),
          if (p.extUrl.isNotEmpty)
            TextButton.icon(onPressed: () => openLink(context, 'Partner link', p.extUrl), icon: const Icon(Icons.open_in_new), label: const Text('Partner site')),
        ]),
        const SizedBox(height: 14),
        const Text('Share this product:', style: TextStyle(fontWeight: FontWeight.bold)),
        Row(children: [
          IconButton(
            tooltip: 'Share on WhatsApp',
            color: const Color(0xFF25D366),
            icon: const Icon(Icons.share),
            onPressed: () => showWhatsAppDialog(context, share: true, preset: 'Check this product: ${p.name} - ${money(p.price)}\n${productLink(p)}'),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.link),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: productLink(p)));
              snack(context, 'Product link copied ✅');
            },
          ),
          IconButton(
            tooltip: 'Ask about this product',
            icon: const Icon(Icons.message_outlined),
            onPressed: () => showWhatsAppDialog(context, preset: 'Hello! I want to know about: ${p.name}'),
          ),
        ]),
      ]);

      return Scaffold(
        appBar: AppBar(title: Text(p.name), actions: [cartButton(context)]),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
          onPressed: () => showWhatsAppDialog(context, preset: 'Hello! I want to know about: ${p.name}'),
          child: const Icon(Icons.chat),
        ),
        body: SingleChildScrollView(
          child: box(Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(
                builder: (c, cons) => cons.maxWidth > 700
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: image), const SizedBox(width: 24), Expanded(child: info)])
                    : Column(children: [image, const SizedBox(height: 16), info]),
              ),
              const Divider(height: 40),
              const Text('Reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (revs.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No reviews yet. Be the first!')),
              for (final r in revs)
                ListTile(
                  leading: CircleAvatar(child: Text(r.userName.isEmpty ? '?' : r.userName[0])),
                  title: Row(children: [Text(r.userName), const SizedBox(width: 8), stars(r.rating.toDouble(), size: 14)]),
                  subtitle: Text(r.comment),
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Write a review', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => rating = i),
                          icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber),
                        ),
                    ]),
                    TextField(controller: comment, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Your comment')),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: submitReview, child: const Text('Submit review')),
                  ]),
                ),
              ),
            ]),
          )),
        ),
      );
    });
  }
}

// -------------------------------- CART --------------------------------------
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return watch(() => Scaffold(
          appBar: AppBar(title: Text('My Cart (${store.cartCount})')),
          body: store.cart.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey), Text('Your cart is empty')]))
              : box(Column(children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(12), children: [
                      for (final c in store.cart)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(children: [
                              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 64, height: 64, child: productImage(c.product))),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('${money(c.product.price)} x ${c.qty} = ${money(c.product.price * c.qty)}'),
                                ]),
                              ),
                              qtyStepper(c.qty, () => store.changeQty(c, -1), () => store.changeQty(c, 1)),
                              IconButton(onPressed: () => store.removeFromCart(c), icon: const Icon(Icons.delete_outline, color: Colors.red)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        _row('Subtotal', money(store.subtotal)),
                        if (store.discountPercent > 0) _row('Membership discount (${store.discountPercent}%)', '-${money(store.discountAmount)}'),
                        _row('Delivery fee', money(store.deliveryFee)),
                        const Divider(),
                        _row('Total', money(store.total), bold: true),
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => goCheckout(context), child: const Text('Proceed to Checkout'))),
                      ]),
                    ),
                  ),
                ])),
        ));
  }
}

Widget _row(String a, String b, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(a, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 18 : null)),
        Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 18 : null)),
      ]),
    );

// ------------------------------ CHECKOUT ------------------------------------
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  late final name = TextEditingController(text: store.currentUser?.name ?? '');
  late final phone = TextEditingController(text: store.currentUser?.phone ?? '');
  late final address = TextEditingController(text: store.currentUser?.address ?? '');
  final trx = TextEditingController();
  String payment = 'COD';
  bool busy = false;

  Future<void> place() async {
    if (busy) return;
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || address.text.trim().isEmpty) {
      return snack(context, 'Please fill name, phone and address');
    }
    if (payment == 'bKash' && trx.text.trim().isEmpty) return snack(context, 'Enter your bKash Transaction ID');
    if (store.cart.isEmpty) return;
    setState(() => busy = true);
    final err = await store.placeOrder(name: name.text.trim(), phone: phone.text.trim(), address: address.text.trim(), payment: payment, trxId: trx.text.trim());
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) return snack(context, err);
    final o = store.lastOrder!;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order placed ✅'),
        content: Text('Your order #${o.id} has been placed.\nTotal: ${money(o.total)}\nPayment: ${o.payment}'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => Scaffold(
          appBar: AppBar(title: const Text('Checkout')),
          body: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Delivery details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Full address', border: OutlineInputBorder())),
                    const SizedBox(height: 20),
                    const Text('Payment method', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 10, children: [
                      ChoiceChip(avatar: const Icon(Icons.money), label: const Text('Cash on Delivery'), selected: payment == 'COD', onSelected: (_) => setState(() => payment = 'COD')),
                      ChoiceChip(avatar: const Icon(Icons.phone_android), label: const Text('bKash'), selected: payment == 'bKash', onSelected: (_) => setState(() => payment = 'bKash')),
                    ]),
                    if (payment == 'bKash')
                      Card(
                        color: const Color(0xFFFCE4EC),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('1. Open your bKash app and Send Money ${money(store.total)} to:\n   📱 ${store.bkashNumber} (Personal)', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            const Text('2. Paste the Transaction ID below.'),
                            const SizedBox(height: 8),
                            TextField(controller: trx, decoration: const InputDecoration(labelText: 'bKash Transaction ID (TrxID)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white)),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          for (final c in store.cart) _row('${c.product.name} x ${c.qty}', money(c.product.price * c.qty)),
                          const Divider(),
                          _row('Subtotal', money(store.subtotal)),
                          if (store.discountPercent > 0) _row('Membership discount', '-${money(store.discountAmount)}'),
                          _row('Delivery fee', money(store.deliveryFee)),
                          const Divider(),
                          _row('Total', money(store.total), bold: true),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: busy ? null : place, child: Text(busy ? 'Placing order...' : 'Place Order'))),
                  ]),
                ),
              ),
            ),
          ),
        ));
  }
}

// ------------------------------- LOGIN --------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool adminMode = false;
  bool hide = true;
  bool busy = false;

  Future<void> submit() async {
    if (busy) return;
    setState(() => busy = true);
    final err = await store.login(email.text.trim(), pass.text, adminOnly: adminMode);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) return snack(context, err);
    if (adminMode) {
      // Admin হলে সরাসরি Admin Panel এ যাবে
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPage()));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(adminMode ? 'Admin Login' : 'Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    logoWidget(size: 36),
                    const SizedBox(width: 8),
                    Expanded(child: Text(adminMode ? 'Admin Login' : 'Welcome back', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    // ছোট Admin বাটন (User লগইন ফর্মের পাশে)
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => adminMode = !adminMode),
                      icon: Icon(adminMode ? Icons.person : Icons.admin_panel_settings, size: 16),
                      label: Text(adminMode ? 'User' : 'Admin'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: hide,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : (adminMode ? 'Login as Admin' : 'Login'))),
                  ),
                  if (!adminMode)
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                        child: const Text("Don't have an account? Register"),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------- REGISTER -------------------------------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  bool busy = false;

  Future<void> submit() async {
    if (busy) return;
    if (name.text.trim().isEmpty || email.text.trim().isEmpty || pass.text.isEmpty) return snack(context, 'Name, email and password are required');
    if (!email.text.contains('@')) return snack(context, 'Enter a valid email');
    if (pass.text.length < 6) return snack(context, 'Password must be at least 6 characters');
    if (pass.text != pass2.text) return snack(context, 'Passwords do not match');
    setState(() => busy = true);
    final err = await store.register(name.text.trim(), email.text.trim(), phone.text.trim(), pass.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (err != null) return snack(context, err);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    Widget f(TextEditingController c, String l, IconData i, {bool obscure = false, TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(controller: c, obscureText: obscure, keyboardType: type, decoration: InputDecoration(labelText: l, prefixIcon: Icon(i), border: const OutlineInputBorder())),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Create account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  f(name, 'Full name', Icons.person_outline),
                  f(email, 'Email', Icons.email_outlined, type: TextInputType.emailAddress),
                  f(phone, 'Phone', Icons.phone_outlined, type: TextInputType.phone),
                  f(pass, 'Password', Icons.lock_outline, obscure: true),
                  f(pass2, 'Confirm password', Icons.lock_outline, obscure: true),
                  SizedBox(width: double.infinity, height: 46, child: FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait...' : 'Register'))),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                    child: const Text('Already have an account? Login'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------- PROFILE ------------------------------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final name = TextEditingController(text: store.currentUser?.name ?? '');
  late final phone = TextEditingController(text: store.currentUser?.phone ?? '');
  late final address = TextEditingController(text: store.currentUser?.address ?? '');
  final newPass = TextEditingController();

  Future<void> save() async {
    final err = await store.saveProfile(name.text.trim(), phone.text.trim(), address.text.trim(), newPass.text);
    if (!mounted) return;
    if (err != null) return snack(context, err);
    newPass.clear();
    snack(context, 'Profile saved ✅');
  }

  @override
  Widget build(BuildContext context) {
    return watch(() {
      final u = store.currentUser;
      if (u == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Please login')));
      final myOrders = store.orders.where((o) => o.userEmail == u.email).toList();
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 30, child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase(), style: const TextStyle(fontSize: 26))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(u.email),
                      Chip(label: Text('Membership: ${u.membership}')),
                    ])),
                  ]),
                  const SizedBox(height: 16),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: newPass, obscureText: true, decoration: const InputDecoration(labelText: 'New password (leave empty to keep)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Save profile')),
                  const Divider(height: 36),
                  const Text('Membership plans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  for (final m in store.memberships)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                        title: Text('${m.name} - ${money(m.price)}'),
                        subtitle: Text('${m.perks}  (${m.discount}% off)'),
                        trailing: u.membership == m.name
                            ? const Chip(label: Text('Current'))
                            : FilledButton(
                                onPressed: () async {
                                  // Demo: আসল অ্যাপে এখানে পেমেন্ট নেওয়া হবে
                                  final err = await store.joinMembership(m.name);
                                  if (!mounted) return;
                                  snack(context, err ?? 'You joined ${m.name} 🎉');
                                },
                                child: const Text('Join'),
                              ),
                      ),
                    ),
                  const Divider(height: 36),
                  const Text('My orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (myOrders.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No orders yet')),
                  for (final o in myOrders)
                    Card(
                      child: ExpansionTile(
                        title: Text('Order #${o.id} • ${money(o.total)}'),
                        subtitle: Text('${o.date} • ${o.payment}  ', style: const TextStyle(fontSize: 12)),
                        leading: CircleAvatar(radius: 6, backgroundColor: statusColor(o.status)),
                        trailing: Text(o.returnRequested && o.status == 'Delivered' ? 'Return requested' : o.status, style: TextStyle(color: statusColor(o.status), fontWeight: FontWeight.bold)),
                        childrenPadding: const EdgeInsets.all(12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final i in o.items) Text('• ${i.name} x ${i.qty}'),
                          const SizedBox(height: 6),
                          Text('Deliver to: ${o.address}'),
                          if (o.status == 'Delivered' && !o.returnRequested)
                            TextButton.icon(
                              onPressed: () async {
                                final r = await formDialog(context, 'Request return', {'Reason': ''}, multiline: {'Reason'});
                                if (r == null) return;
                                final err = await store.requestReturn(o, r['Reason']!);
                                if (!mounted) return;
                                snack(context, err ?? 'Return request sent');
                              },
                              icon: const Icon(Icons.assignment_return),
                              label: const Text('Request return'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      store.logout();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// -------------------------------- FOOTER ------------------------------------
class Footer extends StatelessWidget {
  const Footer({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() {
      Widget col(String title, List<Widget> kids) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 8), ...kids],
          );
      const w = TextStyle(color: Colors.white70);
      return Container(
        width: double.infinity,
        color: const Color(0xFF212121),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Wrap(spacing: 48, runSpacing: 24, children: [
            col(store.siteName, [Text(store.tagline, style: w)]),
            col('Contact', [
              Text('📍 ${store.contactAddress}', style: w),
              Text('📞 ${store.contactPhone}', style: w),
              Text('✉️ ${store.contactEmail}', style: w),
            ]),
            col('Links', [
              for (final l in store.links)
                InkWell(
                  onTap: () => openLink(context, l.label, l.url),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('🔗 ${l.label}', style: const TextStyle(color: Colors.lightBlueAccent))),
                ),
            ]),
          ]),
          const Divider(color: Colors.white24, height: 32),
          Text(store.footerText, style: w, textAlign: TextAlign.center),
        ]),
      );
    });
  }
}

// ============================================================================
// 6. ADMIN PANEL
// ============================================================================

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int tab = 0;
  final titles = const ['Dashboard', 'Site Branding', 'Hero Images', 'Products', 'Categories', 'Membership', 'Orders', 'Reviews', 'Users'];
  final icons = const [
    Icons.dashboard, Icons.brush, Icons.image, Icons.inventory_2, Icons.category,
    Icons.workspace_premium, Icons.receipt_long, Icons.reviews, Icons.people,
  ];

  Widget body() {
    switch (tab) {
      case 0:
        return const AdminDashboard();
      case 1:
        return const AdminBranding();
      case 2:
        return const AdminHero();
      case 3:
        return const AdminProducts();
      case 4:
        return const AdminCategories();
      case 5:
        return const AdminMembership();
      case 6:
        return const AdminOrders();
      case 7:
        return const AdminReviews();
      default:
        return const AdminUsers();
    }
  }

  Widget menu({required bool inDrawer}) => ListView(children: [
        if (inDrawer) const SizedBox(height: 40),
        for (var i = 0; i < titles.length; i++)
          ListTile(
            leading: Icon(icons[i]),
            title: Text(titles[i]),
            selected: tab == i,
            onTap: () {
              setState(() => tab = i);
              if (inDrawer) Navigator.pop(context);
            },
          ),
        const Divider(),
        ListTile(leading: const Icon(Icons.storefront), title: const Text('View Website'), onTap: () => Navigator.pop(context)),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Logout', style: TextStyle(color: Colors.red)),
          onTap: () {
            store.logout();
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return watch(() {
      if (store.currentUser?.isAdmin != true) {
        return Scaffold(appBar: AppBar(), body: const Center(child: Text('Admin login required')));
      }
      return LayoutBuilder(builder: (context, cons) {
        final wide = cons.maxWidth >= 850;
        return Scaffold(
          appBar: AppBar(
            title: Text('Admin • ${titles[tab]}'),
            actions: [
              // database এ save হচ্ছে কিনা তার আইকন
              Tooltip(
                message: store.syncStatus.isEmpty ? 'Connected' : store.syncStatus,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    store.syncError ? Icons.cloud_off : (store.saving ? Icons.cloud_upload : Icons.cloud_done),
                    color: store.syncError ? Colors.red : null,
                  ),
                ),
              ),
              IconButton(tooltip: 'Reload from database', icon: const Icon(Icons.sync), onPressed: () => store.loadAdmin()),
              IconButton(tooltip: 'View site', icon: const Icon(Icons.storefront), onPressed: () => Navigator.pop(context)),
              IconButton(
                tooltip: 'Logout',
                icon: const Icon(Icons.logout),
                onPressed: () {
                  store.logout();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ],
          ),
          drawer: wide ? null : Drawer(child: menu(inDrawer: true)),
          body: Row(children: [
            if (wide) SizedBox(width: 230, child: Material(color: Colors.blueGrey.shade50, child: menu(inDrawer: false))),
            Expanded(
              child: Column(children: [
                if (store.syncError)
                  Container(width: double.infinity, color: Colors.red.shade100, padding: const EdgeInsets.all(8), child: Text(store.syncStatus)),
                Expanded(child: body()),
              ]),
            ),
          ]),
        );
      });
    });
  }
}

// ---- Admin: ছোট সাহায্যকারী ----
Widget adminHeader(String title, {String? buttonText, VoidCallback? onAdd}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        if (onAdd != null) FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(buttonText ?? 'Add')),
      ]),
    );

Widget statCard(String title, String value, IconData icon, Color color) => SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ])),
          ]),
        ),
      ),
    );

// ------------------------------ DASHBOARD -----------------------------------
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() {
      final valid = store.orders.where((o) => o.status != 'Cancelled' && o.status != 'Returned');
      final sales = valid.fold(0.0, (s, o) => s + o.total);
      final totalOrders = store.orders.length;
      return ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          statCard('Total sales', money(sales), Icons.payments, Colors.green),
          statCard('Orders', '$totalOrders', Icons.receipt_long, Colors.blue),
          statCard('Pending orders', '${store.orders.where((o) => o.status == 'Pending').length}', Icons.hourglass_top, Colors.orange),
          statCard('Products', '${store.products.length}', Icons.inventory_2, Colors.purple),
          statCard('Users', '${store.users.length}', Icons.people, Colors.teal),
          statCard('Pending reviews', '${store.reviews.where((r) => !r.approved).length}', Icons.reviews, Colors.pink),
          statCard('Return requests', '${store.orders.where((o) => o.returnRequested && o.status != 'Returned').length}', Icons.assignment_return, Colors.red),
        ]),
        const SizedBox(height: 24),
        const Text('Orders by status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final s in orderStatuses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 90, child: Text(s)),
              Expanded(
                child: LinearProgressIndicator(
                  value: totalOrders == 0 ? 0 : store.orders.where((o) => o.status == s).length / totalOrders,
                  color: statusColor(s),
                  minHeight: 10,
                ),
              ),
              SizedBox(width: 30, child: Text('  ${store.orders.where((o) => o.status == s).length}')),
            ]),
          ),
        const SizedBox(height: 24),
        const Text('Recent orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (store.orders.isEmpty) const Text('No orders yet'),
        for (final o in store.orders.take(5))
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 6, backgroundColor: statusColor(o.status)),
            title: Text('#${o.id} • ${o.userName}'),
            subtitle: Text('${o.date} • ${o.payment}'),
            trailing: Text(money(o.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 16),
        const Text('Low stock (5 or less)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (!store.products.any((p) => p.stock <= 5)) const Text('All products have enough stock 👍'),
        for (final p in store.products.where((p) => p.stock <= 5))
          ListTile(dense: true, leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text(p.name), trailing: Text('${p.stock} left')),
      ]);
    });
  }
}

// ------------------------------ BRANDING ------------------------------------
class AdminBranding extends StatefulWidget {
  const AdminBranding({super.key});
  @override
  State<AdminBranding> createState() => _AdminBrandingState();
}

class _AdminBrandingState extends State<AdminBranding> {
  late final Map<String, TextEditingController> c = {
    'Site name': TextEditingController(text: store.siteName),
    'Logo (emoji or text)': TextEditingController(text: store.logoText),
    'Logo image URL (optional)': TextEditingController(text: store.logoUrl),
    'Tagline': TextEditingController(text: store.tagline),
    'Announcement bar text': TextEditingController(text: store.announcement),
    'Footer text': TextEditingController(text: store.footerText),
    'Currency symbol': TextEditingController(text: store.currency),
    'Website URL': TextEditingController(text: store.siteUrl),
    'WhatsApp number (with country code)': TextEditingController(text: store.whatsapp),
    'bKash number': TextEditingController(text: store.bkashNumber),
    'Contact email': TextEditingController(text: store.contactEmail),
    'Contact phone': TextEditingController(text: store.contactPhone),
    'Contact address': TextEditingController(text: store.contactAddress),
    'Products per page': TextEditingController(text: '${store.perPage}'),
    'Delivery fee': TextEditingController(text: store.deliveryFee.toStringAsFixed(0)),
  };

  void save() {
    String t(String k) => c[k]!.text.trim();
    store.siteName = t('Site name');
    store.logoText = t('Logo (emoji or text)');
    store.logoUrl = t('Logo image URL (optional)');
    store.tagline = t('Tagline');
    store.announcement = t('Announcement bar text');
    store.footerText = t('Footer text');
    store.currency = t('Currency symbol');
    store.siteUrl = t('Website URL');
    store.whatsapp = t('WhatsApp number (with country code)');
    store.bkashNumber = t('bKash number');
    store.contactEmail = t('Contact email');
    store.contactPhone = t('Contact phone');
    store.contactAddress = t('Contact address');
    final pp = int.tryParse(t('Products per page')) ?? 6;
    store.perPage = pp < 1 ? 1 : pp;
    store.deliveryFee = double.tryParse(t('Delivery fee')) ?? 0;
    store.update(); // update() ডাকলেই database এ save হয়ে যায়
    snack(context, 'Saved ✅ - check the website');
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Site Branding & Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (final k in c.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: c[k], decoration: InputDecoration(labelText: k, border: const OutlineInputBorder())),
            ),
          SwitchListTile(
            title: const Text('Show announcement bar'),
            value: store.showAnnouncement,
            onChanged: (v) {
              store.showAnnouncement = v;
              store.update();
            },
          ),
          const Text('Theme color', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(spacing: 10, children: [
            for (final e in palette.entries)
              GestureDetector(
                onTap: () {
                  store.primaryColor = e.value;
                  store.update();
                },
                child: Tooltip(
                  message: e.key,
                  child: CircleAvatar(
                    backgroundColor: Color(e.value),
                    child: store.primaryColor == e.value ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('Save settings')),
          const Divider(height: 40),
          Row(children: [
            const Expanded(child: Text('Third-party links (Footer & Menu)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            FilledButton.icon(
              onPressed: () async {
                final r = await formDialog(context, 'Add link', {'Label': '', 'URL': 'https://'});
                if (r == null || r['Label']!.isEmpty) return;
                store.links.add(LinkItem(r['Label']!, r['URL']!));
                store.update();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ]),
          for (final l in List<LinkItem>.from(store.links))
            Card(
              child: ListTile(
                leading: const Icon(Icons.link),
                title: Text(l.label),
                subtitle: Text(l.url),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final r = await formDialog(context, 'Edit link', {'Label': l.label, 'URL': l.url});
                      if (r == null) return;
                      l.label = r['Label']!;
                      l.url = r['URL']!;
                      store.update();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      store.links.remove(l);
                      store.update();
                    },
                  ),
                ]),
              ),
            ),
        ]));
  }
}

// ------------------------------ HERO IMAGES ---------------------------------
class AdminHero extends StatelessWidget {
  const AdminHero({super.key});

  Future<void> upload(BuildContext context, HeroSlide s) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'webm', 'mkv'],
    );
    if (res.isEmpty) return;
    final f = res.first;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      return snack(context, 'Could not read file');
    }
    try {
      final d = await Api.uploadFile(bytes, f.name);
      s.imageUrl = (d['secure_url'] ?? d['url'] ?? '').toString();
      s.mediaType = (d['resource_type'] ?? 'image').toString();
      s.publicId = (d['public_id'] ?? '').toString();
      store.update();
      snack(context, 'Uploaded ✅');
    } catch (e) {
      snack(context, 'Upload failed: $e');
    }
  }

  Future<void> edit(BuildContext context, [HeroSlide? s]) async {
    final r = await formDialog(
      context,
      s == null ? 'Add slide' : 'Edit slide',
      {
        'Title': s?.title ?? '',
        'Subtitle': s?.subtitle ?? '',
        'Button text': s?.buttonText ?? 'Shop Now',
        'Image URL (optional)': s?.imageUrl ?? '',
        'Button opens category': s?.category ?? 'All',
        'Background color': s == null ? 'Blue' : colorName(s.colorValue),
      },
      dropdowns: {'Button opens category': ['All', ...store.categories], 'Background color': palette.keys.toList()},
    );
    if (r == null || r['Title']!.isEmpty) return;
    final slide = s ?? HeroSlide(id: store.nextId(), title: '');
    slide.title = r['Title']!;
    slide.subtitle = r['Subtitle']!;
    slide.buttonText = r['Button text']!;
    slide.imageUrl = r['Image URL (optional)']!;
    slide.category = r['Button opens category']!;
    slide.colorValue = palette[r['Background color']]!;
    if (s == null) store.slides.add(slide);
    store.update();
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Hero Slides (${store.slides.length})', buttonText: 'Add slide', onAdd: () => edit(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final s in List<HeroSlide>.from(store.slides))
                Card(
                  child: ListTile(
                    leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: Color(s.colorValue), borderRadius: BorderRadius.circular(8))),
                    title: Text(s.title),
                    subtitle: Text('${s.subtitle}\nButton: ${s.buttonText} → ${s.category}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.cloud_upload), tooltip: 'Upload image/video', onPressed: () => upload(context, s)),
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(context, s)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await confirm(context, 'Delete this slide?')) {
                            store.slides.remove(s);
                            store.update();
                          }
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]));
  }
}

// -------------------------------- PRODUCTS ----------------------------------
class AdminProducts extends StatelessWidget {
  const AdminProducts({super.key});

  Future<void> upload(BuildContext context, Product p) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'webm', 'mkv'],
    );
    if (res.isEmpty) return;
    final f = res.first;
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      return snack(context, 'Could not read file');
    }
    try {
      final d = await Api.uploadFile(bytes, f.name);
      p.imageUrl = (d['secure_url'] ?? d['url'] ?? '').toString();
      p.mediaType = (d['resource_type'] ?? 'image').toString();
      p.publicId = (d['public_id'] ?? '').toString();
      if (p.imageUrl.isNotEmpty && p.colorValue == 0) p.colorValue = 0xFF42A5F5;
      store.update();
      snack(context, 'Uploaded ✅');
    } catch (e) {
      snack(context, 'Upload failed: $e');
    }
  }

  Future<void> edit(BuildContext context, [Product? p]) async {
    if (store.categories.isEmpty) return snack(context, 'Add a category first');
    final r = await formDialog(
      context,
      p == null ? 'Add product' : 'Edit product',
      {
        'Name': p?.name ?? '',
        'Price': p?.price.toStringAsFixed(0) ?? '',
        'Old price (0 = none)': p?.oldPrice.toStringAsFixed(0) ?? '0',
        'Stock': p?.stock.toString() ?? '10',
        'Category': p?.category ?? store.categories.first,
        'Image URL (optional)': p?.imageUrl ?? '',
        'Partner link (optional)': p?.extUrl ?? '',
        'Color (if no image)': p == null ? 'Blue' : colorName(p.colorValue),
        'Description': p?.desc ?? '',
      },
      dropdowns: {'Category': store.categories, 'Color (if no image)': palette.keys.toList()},
      multiline: {'Description'},
    );
    if (r == null || r['Name']!.isEmpty) return;
    final prod = p ?? Product(id: store.nextId(), name: '', price: 0, category: store.categories.first);
    prod.name = r['Name']!;
    prod.price = double.tryParse(r['Price']!) ?? 0;
    prod.oldPrice = double.tryParse(r['Old price (0 = none)']!) ?? 0;
    prod.stock = int.tryParse(r['Stock']!) ?? 0;
    prod.category = r['Category']!;
    prod.imageUrl = r['Image URL (optional)']!;
    prod.extUrl = r['Partner link (optional)']!;
    prod.colorValue = palette[r['Color (if no image)']]!;
    prod.desc = r['Description']!;
    if (p == null) store.products.insert(0, prod);
    store.update();
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Products (${store.products.length})', buttonText: 'Add product', onAdd: () => edit(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final p in List<Product>.from(store.products))
                Card(
                  child: ListTile(
                    leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 50, height: 50, child: productImage(p))),
                    title: Text(p.name),
                    subtitle: Text('${p.category} • ${money(p.price)} • Stock: ${p.stock}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.cloud_upload), tooltip: 'Upload image/video', onPressed: () => upload(context, p)),
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(context, p)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await confirm(context, 'Delete "${p.name}"?')) {
                            store.products.remove(p);
                            store.cart.removeWhere((c) => c.product.id == p.id);
                            store.update();
                          }
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]));
  }
}

// ------------------------------- CATEGORIES ---------------------------------
class AdminCategories extends StatelessWidget {
  const AdminCategories({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Categories (${store.categories.length})', buttonText: 'Add category', onAdd: () async {
            final r = await formDialog(context, 'Add category', {'Name': ''});
            if (r == null || r['Name']!.isEmpty || store.categories.contains(r['Name'])) return;
            store.categories.add(r['Name']!);
            store.update();
          }),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final cat in List<String>.from(store.categories))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.category),
                    title: Text(cat),
                    subtitle: Text('${store.products.where((p) => p.category == cat).length} products'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final r = await formDialog(context, 'Rename category', {'Name': cat});
                          if (r == null || r['Name']!.isEmpty) return;
                          final i = store.categories.indexOf(cat);
                          store.categories[i] = r['Name']!;
                          for (final p in store.products) {
                            if (p.category == cat) p.category = r['Name']!;
                          }
                          for (final s in store.slides) {
                            if (s.category == cat) s.category = r['Name']!;
                          }
                          store.update();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (store.products.any((p) => p.category == cat)) {
                            return snack(context, 'Move or delete the products of this category first');
                          }
                          if (await confirm(context, 'Delete category "$cat"?')) {
                            store.categories.remove(cat);
                            store.update();
                          }
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]));
  }
}

// ------------------------------- MEMBERSHIP ---------------------------------
class AdminMembership extends StatelessWidget {
  const AdminMembership({super.key});

  Future<void> edit(BuildContext context, [Membership? m]) async {
    final r = await formDialog(context, m == null ? 'Add plan' : 'Edit plan', {
      'Plan name': m?.name ?? '',
      'Price': m?.price.toStringAsFixed(0) ?? '',
      'Discount %': m?.discount.toString() ?? '5',
      'Perks': m?.perks ?? '',
    });
    if (r == null || r['Plan name']!.isEmpty) return;
    final price = double.tryParse(r['Price']!) ?? 0;
    final disc = int.tryParse(r['Discount %']!) ?? 0;
    if (m == null) {
      store.memberships.add(Membership(id: store.nextId(), name: r['Plan name']!, price: price, discount: disc, perks: r['Perks']!));
    } else {
      // নাম বদলালে ইউজারদের মেম্বারশিপও আপডেট হবে
      for (final u in store.users) {
        if (u.membership == m.name) u.membership = r['Plan name']!;
      }
      m.name = r['Plan name']!;
      m.price = price;
      m.discount = disc;
      m.perks = r['Perks']!;
    }
    store.update();
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Membership Plans', buttonText: 'Add plan', onAdd: () => edit(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final m in List<Membership>.from(store.memberships))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                    title: Text('${m.name} • ${money(m.price)} • ${m.discount}% off'),
                    subtitle: Text('${m.perks}\nMembers: ${store.users.where((u) => u.membership == m.name).length}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(context, m)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (await confirm(context, 'Delete plan "${m.name}"?')) {
                            for (final u in store.users) {
                              if (u.membership == m.name) u.membership = 'None';
                            }
                            store.memberships.remove(m);
                            store.update();
                          }
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]));
  }
}

// -------------------------------- ORDERS ------------------------------------
class AdminOrders extends StatelessWidget {
  const AdminOrders({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Orders (${store.orders.length})'),
          Expanded(
            child: store.orders.isEmpty
                ? const Center(child: Text('No orders yet'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final o in List<Order>.from(store.orders))
                      Card(
                        child: ExpansionTile(
                          leading: CircleAvatar(radius: 6, backgroundColor: statusColor(o.status)),
                          title: Text('#${o.id} • ${o.userName} • ${money(o.total)}'),
                          subtitle: Text('${o.date} • ${o.payment} • ${o.status}${o.returnRequested ? '  ⚠ RETURN REQUESTED' : ''}'),
                          childrenPadding: const EdgeInsets.all(12),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final i in o.items) Text('• ${i.name} x ${i.qty}  (${money(i.price * i.qty)})'),
                            const SizedBox(height: 8),
                            Text('Customer: ${o.userName} (${o.userEmail})'),
                            Text('Phone: ${o.phone}'),
                            Text('Address: ${o.address}'),
                            if (o.trxId.isNotEmpty) Text('bKash TrxID: ${o.trxId}'),
                            if (o.returnRequested) Text('Return reason: ${o.returnReason}', style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              const Text('Status: '),
                              DropdownButton<String>(
                                value: o.status,
                                items: [for (final s in orderStatuses) DropdownMenuItem(value: s, child: Text(s))],
                                onChanged: (v) => store.setStatus(o, v!),
                              ),
                              if (o.returnRequested && o.status != 'Returned')
                                FilledButton(onPressed: () => store.setStatus(o, 'Returned'), child: const Text('Approve return')),
                              TextButton.icon(
                                onPressed: () async {
                                  if (await confirm(context, 'Delete order #${o.id}?')) {
                                    store.orders.remove(o);
                                    store.update();
                                  }
                                },
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ]),
                          ],
                        ),
                      ),
                  ]),
          ),
        ]));
  }
}

// -------------------------------- REVIEWS -----------------------------------
class AdminReviews extends StatelessWidget {
  const AdminReviews({super.key});
  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Reviews (${store.reviews.length})'),
          Expanded(
            child: store.reviews.isEmpty
                ? const Center(child: Text('No reviews yet'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final r in List<Review>.from(store.reviews))
                      Card(
                        child: ListTile(
                          leading: Icon(r.approved ? Icons.check_circle : Icons.pending, color: r.approved ? Colors.green : Colors.orange),
                          title: Row(children: [
                            Flexible(child: Text(store.products.where((p) => p.id == r.productId).map((p) => p.name).join(), overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            stars(r.rating.toDouble(), size: 14),
                          ]),
                          subtitle: Text('${r.userName}: ${r.comment}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(
                              onPressed: () {
                                r.approved = !r.approved;
                                store.update();
                              },
                              child: Text(r.approved ? 'Hide' : 'Approve'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                store.reviews.remove(r);
                                store.update();
                              },
                            ),
                          ]),
                        ),
                      ),
                  ]),
          ),
        ]));
  }
}

// --------------------------------- USERS ------------------------------------
class AdminUsers extends StatelessWidget {
  const AdminUsers({super.key});

  Future<void> edit(BuildContext context, [AppUser? u]) async {
    final r = await formDialog(
      context,
      u == null ? 'Add user' : 'Edit user',
      {
        'Name': u?.name ?? '',
        'Email': u?.email ?? '',
        'Phone': u?.phone ?? '',
        'Address': u?.address ?? '',
        'Password (empty = keep old)': '',
        'Membership': u?.membership ?? 'None',
        'Role': u == null || !u.isAdmin ? 'user' : 'admin',
        'Status': u != null && u.blocked ? 'Blocked' : 'Active',
      },
      dropdowns: {
        'Membership': ['None', ...store.memberships.map((m) => m.name)],
        'Role': ['user', 'admin'],
        'Status': ['Active', 'Blocked'],
      },
    );
    if (r == null || r['Name']!.isEmpty || r['Email']!.isEmpty) return;
    final pw = r['Password (empty = keep old)']!;
    if (u == null && pw.length < 6) return snack(context, 'New user needs a password (6+ characters)');
    final user = u ?? AppUser(id: store.nextId(), name: '', email: '');
    user.name = r['Name']!;
    user.email = r['Email']!;
    user.phone = r['Phone']!;
    user.address = r['Address']!;
    user.password = pw; // ফাঁকা থাকলে পুরনো পাসওয়ার্ডই থাকবে
    user.membership = r['Membership']!;
    user.isAdmin = r['Role'] == 'admin';
    user.blocked = r['Status'] == 'Blocked';
    if (u == null) store.users.add(user);
    store.update();
  }

  @override
  Widget build(BuildContext context) {
    return watch(() => Column(children: [
          adminHeader('Users (${store.users.length})', buttonText: 'Add user', onAdd: () => edit(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final u in List<AppUser>.from(store.users))
                Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase())),
                    title: Text('${u.name}${u.isAdmin ? '  (admin)' : ''}'),
                    subtitle: Text('${u.email} • ${u.phone}\nMembership: ${u.membership} • ${u.blocked ? 'BLOCKED' : 'Active'}'),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit), onPressed: () => edit(context, u)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (u.id == store.currentUser?.id) return snack(context, 'You cannot delete yourself');
                          if (await confirm(context, 'Delete user "${u.name}"?')) {
                            store.users.remove(u);
                            store.update();
                          }
                        },
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ]));
  }
}
