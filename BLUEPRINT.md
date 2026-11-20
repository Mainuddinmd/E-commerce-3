# MyShop — System Blueprint (Frontend + Backend)

## 1. High-Level Architecture

```mermaid
flowchart LR
    subgraph Client["Flutter Frontend (Web / Chrome)"]
        UI["UI Screens\nHome, Product, Cart, Checkout\nLogin, Register, Profile\nAdmin Panel"]
        Store["Store (ChangeNotifier)\nproducts, slides, orders, users, settings"]
        Api["Api (http)\ncall() + uploadFile()"]
    end

    subgraph Backend["Node.js + Express (backend/server.js)"]
        Auth["Auth Middleware\nBearer token -> sessions Map"]
        Public["Public API\n/api/health\n/api/data\n/api/register\n/api/login"]
        Customer["Customer API\n/api/me\n/api/orders\n/api/reviews"]
        Admin["Admin API\n/api/admin/*\n/api/admin/upload"]
        Seed["Seed (first run)\nsettings, products, slides,\nmemberships, reviews, admin user"]
    end

    subgraph Data["Data & Storage"]
        Mongo[(MongoDB\nusers, products, orders,\nsettings, slides, memberships,\nreviews)]
        Cloudinary[(Cloudinary\nimages & videos\nq_auto, f_auto)]
    end

    UI --> Store
    Store --> Api
    Api -- "JSON REST (http://localhost:3000)" --> Public
    Api --> Customer
    Api --> Admin
    Public --> Auth
    Customer --> Auth
    Admin --> Auth
    Auth --> Mongo
    Public --> Mongo
    Customer --> Mongo
    Admin --> Mongo
    Admin -- "multipart upload" --> Cloudinary
    Cloudinary -- "secure_url + public_id" --> Admin
    Admin -- "URL + metadata" --> Mongo
    Seed --> Mongo
```

## 2. Request Flow (Admin Media Upload)

```mermaid
sequenceDiagram
    participant A as Admin (Flutter)
    participant F as FilePicker
    participant B as Backend /api/admin/upload
    participant C as Cloudinary
    participant M as MongoDB

    A->>F: pick image/video
    F-->>A: bytes + filename
    A->>B: POST multipart (Authorization: Bearer token)
    B->>B: auth + adminOnly check
    B->>B: multer parses file (memory)
    B->>C: uploader.upload (resource_type:auto, q_auto, f_auto)
    C-->>B: secure_url, public_id, resource_type
    B-->>A: { url, public_id, resource_type, ... }
    A->>A: set product.imageUrl / slide.imageUrl
    A->>A: set mediaType, publicId
    A->>B: store.update() -> POST /api/admin/products (upsert)
    B->>M: updateOne (imageUrl, mediaType, publicId)
    M-->>B: ok
    B-->>A: { ok: true }
```

## 3. Data Flow (Normal User)

```mermaid
sequenceDiagram
    participant U as User (Flutter)
    participant B as Backend
    participant M as MongoDB

    U->>B: GET /api/data
    B->>M: find settings, products, slides, memberships, reviews
    M-->>B: documents (projection: _id=0)
    B-->>U: JSON (no passwordHash)
    U->>U: Store._applySettings, products, slides, ...
    U->>B: POST /api/orders (auth)
    B->>M: decrement stock, insert order
    M-->>B: ok
    B-->>U: order
```

## 4. Data Model (MongoDB Collections)

```mermaid
erDiagram
    USERS ||--o{ ORDERS : places
    USERS {
        int id PK
        string name
        string email
        string passwordHash
        string membership
        bool isAdmin
        bool blocked
    }
    PRODUCTS {
        int id PK
        string name
        double price
        double oldPrice
        string category
        string desc
        string imageUrl
        string mediaType
        string publicId
        string extUrl
        int stock
        int colorValue
    }
    SLIDES {
        int id PK
        string title
        string subtitle
        string buttonText
        string imageUrl
        string mediaType
        string publicId
        string category
        int colorValue
    }
    ORDERS {
        int id PK
        int userId FK
        string status
        array items
        double total
        string date
    }
    SETTINGS {
        string _id
        string siteName
        string logoUrl
        array categories
        array links
        double deliveryFee
    }
    MEMBERSHIPS {
        int id PK
        string name
        double price
        int discount
        string perks
    }
    REVIEWS {
        int id PK
        int productId FK
        int rating
        string comment
        bool approved
    }
```

## 5. Auth Flow

```mermaid
flowchart TD
    L["Login or Register"] -->|"POST /api/login or /api/register"| B["Backend"]
    B -->|"verify password scrypt"| M["MongoDB users"]
    M -->|"user doc"| B
    B -->|"crypto.randomBytes token"| S["sessions Map token to userId"]
    S -->|"token plus publicUser"| F["Flutter Api.token"]
    F -->|"Authorization Bearer token"| R["Protected routes"]
    R -->|"auth middleware"| S
    S -->|"userId"| M
```

## 6. Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Dart) — Web, Chrome |
| HTTP client | package:http |
| File picker | package:file_picker |
| Backend | Node.js + Express |
| Database | MongoDB (mongodb driver) |
| Media storage | Cloudinary (cloudinary v2 + multer) |
| Auth | Token-based (in-memory sessions, crypto) |
| Deployment | Vercel (frontend SPA), backend separate |

## 7. Folder Structure

```
E-commerce-3/
├── backend/
│   ├── server.js          # Express API + MongoDB + Cloudinary upload
│   ├── package.json
│   └── node_modules/
├── frontend/
│   ├── lib/main.dart      # Flutter app (UI + Store + Api + Models)
│   ├── pubspec.yaml
│   └── build/web/         # flutter build web output
├── vercel.json            # SPA routing rewrites
└── (no root server.js / main.dart - moved into folders)
```

## 8. API Endpoints Summary

**Public:** `GET /api/health`, `GET /api/data`, `POST /api/register`, `POST /api/login`

**Customer (auth):** `PUT /api/me`, `POST /api/me/membership`, `GET /api/my/orders`, `POST /api/orders`, `POST /api/orders/:id/return`, `POST /api/reviews`

**Admin (auth + adminOnly):** `GET /api/admin/data`, `PUT /api/admin/settings`, `POST /api/admin/:col/upsert`, `POST /api/admin/:col/delete`, `POST /api/admin/upload`
```
