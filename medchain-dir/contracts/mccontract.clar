;; Medical Supply Chain Management 
;; Core functionality for basic supply tracking and distribution

;; Core Administrator Setup
(define-data-var network-admin principal tx-sender)

;; Response Codes
(define-constant UNAUTHORIZED (err u301))
(define-constant INVALID-PACKAGE (err u302))
(define-constant DUPLICATE-PACKAGE (err u303))
(define-constant MISSING-PACKAGE (err u304))
(define-constant SUPPLY-DEPLETED (err u305))
(define-constant INVALID-PATIENT (err u306))
(define-constant FACILITY-INVALID (err u310))
(define-constant ADMIN-RESTRICTED (err u313))
(define-constant DATA-ERROR (err u314))

;; Operational Parameters
(define-constant STORAGE-MIN-TEMP (- 75))
(define-constant STORAGE-MAX-TEMP 5)
(define-constant MINIMUM-LENGTH u1)
(define-constant TIMESTAMP block-height)

;; Data Structures
(define-map inventory-tracker
    { package-id: (string-ascii 32) }
    {
        manufacturer: (string-ascii 50),
        item-name: (string-ascii 50),
        production-date: uint,
        expiration-window: uint,
        remaining-stock: uint,
        required-temp: int,
        package-state: (string-ascii 20),
        storage-location: (string-ascii 100)
    }
)

(define-map facility-registry
    (string-ascii 100)
    {
        location: (string-ascii 200),
        patient-limit: uint,
        current-stock: uint,
        temperature-log: (list 100 {
            scan-time: uint,
            temperature: int
        })
    }
)

(define-map provider-directory 
    principal 
    {
        role: (string-ascii 20),
        facility-name: (string-ascii 100),
        license-expiry: uint
    }
)

;; Utility Functions
(define-private (is-network-admin)
    (is-eq tx-sender (var-get network-admin))
)

(define-private (validate-user (entity principal))
    (and 
        (not (is-eq entity tx-sender))
        (not (is-eq entity (var-get network-admin)))
        (match (principal-destruct? entity)
            success true
            error false)
    )
)

;; Administrative Functions
(define-public (update-admin (new-admin principal))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (validate-user new-admin) DATA-ERROR)
        (ok (var-set network-admin new-admin))
    )
)

;; Package Management
(define-public (register-package 
    (package-id (string-ascii 32))
    (details {
        manufacturer: (string-ascii 50),
        item-name: (string-ascii 50),
        production-date: uint,
        expiration-window: uint,
        remaining-stock: uint,
        required-temp: int,
        storage-location: (string-ascii 100)
    }))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (is-none (map-get? inventory-tracker {package-id: package-id})) DUPLICATE-PACKAGE)
        (ok (map-set inventory-tracker 
            {package-id: package-id}
            (merge details {package-state: "active"})))
    )
)

;; Facility Management
(define-public (register-facility
    (facility-id (string-ascii 100))
    (details {
        location: (string-ascii 200),
        patient-limit: uint,
        current-stock: uint
    }))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (is-none (map-get? facility-registry facility-id)) FACILITY-INVALID)
        (ok (map-set facility-registry
            facility-id
            (merge details {temperature-log: (list)})))
    )
)

;; Provider Management
(define-public (register-provider
    (provider principal)
    (details {
        role: (string-ascii 20),
        facility-name: (string-ascii 100),
        license-expiry: uint
    }))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (validate-user provider) DATA-ERROR)
        (ok (map-set provider-directory provider details))
    )
)

;; Query Functions
(define-read-only (get-package-details (package-id (string-ascii 32)))
    (map-get? inventory-tracker {package-id: package-id})
)

(define-read-only (get-facility-details (facility-id (string-ascii 100)))
    (map-get? facility-registry facility-id)
)

(define-read-only (get-provider-details (provider principal))
    (map-get? provider-directory provider)
)

(define-read-only (verify-provider-status (provider principal))
    (match (map-get? provider-directory provider)
        details (>= (get license-expiry details) TIMESTAMP)
        false
    )
)