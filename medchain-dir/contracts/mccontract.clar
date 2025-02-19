;; Medical Supply Chain Management Contract

(define-data-var network-admin principal tx-sender)

;; Response Codes
(define-constant UNAUTHORIZED (err u301))
(define-constant INVALID-PACKAGE (err u302))
(define-constant DUPLICATE-PACKAGE (err u303))
(define-constant MISSING-PACKAGE (err u304))
(define-constant SUPPLY-DEPLETED (err u305))
(define-constant INVALID-PATIENT (err u306))
(define-constant DUPLICATE-PATIENT (err u307))
(define-constant STORAGE-VIOLATION (err u308))
(define-constant PACKAGE-OUTDATED (err u309))
(define-constant FACILITY-INVALID (err u310))
(define-constant DOSAGE-EXCEEDED (err u311))
(define-constant INTERVAL-ERROR (err u312))
(define-constant ADMIN-RESTRICTED (err u313))
(define-constant DATA-ERROR (err u314))
(define-constant DATE-INVALID (err u315))
(define-constant CAPACITY-ERROR (err u316))

;; Operational Parameters
(define-constant STORAGE-MIN-TEMP (- 75))
(define-constant STORAGE-MAX-TEMP 5)
(define-constant INTERVAL-REQUIRED u28)
(define-constant MAX-TREATMENT-SERIES u4)
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
        temp-violations: uint,
        storage-location: (string-ascii 100),
        handling-notes: (string-ascii 500)
    }
)

(define-map patient-records
    { patient-id: (string-ascii 32) }
    {
        treatment-history: (list 10 {
            package-used: (string-ascii 32),
            treatment-date: uint,
            medicine-given: (string-ascii 50),
            dose-number: uint,
            medical-provider: principal,
            facility-name: (string-ascii 100),
            followup-date: (optional uint)
        }),
        completed-treatments: uint,
        adverse-reactions: (list 5 (string-ascii 200)),
        medical-exemption: (optional (string-ascii 200))
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

(define-private (validate-string-32 (input (string-ascii 32)))
    (> (len input) MINIMUM-LENGTH)
)

(define-private (validate-string-20 (input (string-ascii 20)))
    (> (len input) MINIMUM-LENGTH)
)

(define-private (validate-string-50 (input (string-ascii 50)))
    (> (len input) MINIMUM-LENGTH)
)

(define-private (validate-string-100 (input (string-ascii 100)))
    (> (len input) MINIMUM-LENGTH)
)

(define-private (validate-string-200 (input (string-ascii 200)))
    (> (len input) MINIMUM-LENGTH)
)

(define-private (validate-future-time (timestamp uint))
    (> timestamp TIMESTAMP)
)

(define-private (validate-limit (limit uint))
    (> limit u0)
)

;; Query Functions
(define-read-only (get-admin)
    (ok (var-get network-admin))
)

(define-read-only (verify-provider-status (provider principal))
    (match (map-get? provider-directory provider)
        details (>= (get license-expiry details) TIMESTAMP)
        false
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

;; Data Retrieval Functions
(define-read-only (get-package-details (package-id (string-ascii 32)))
    (map-get? inventory-tracker {package-id: package-id})
)

(define-read-only (get-patient-details (patient-id (string-ascii 32)))
    (map-get? patient-records {patient-id: patient-id})
)

(define-read-only (get-facility-details (facility-id (string-ascii 100)))
    (map-get? facility-registry facility-id)
)

(define-read-only (check-package-validity (package-id (string-ascii 32)))
    (match (map-get? inventory-tracker {package-id: package-id})
        details (and
            (is-eq (get package-state details) "active")
            (> (get remaining-stock details) u0)
            (<= TIMESTAMP (get expiration-window details))
            (<= (get temp-violations details) u2))
        false
    )
)