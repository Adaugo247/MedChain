;; Medical Supply Chain Management 
;; Added patient tracking and treatment history

;; Core Administrator Setup
(define-data-var network-admin principal tx-sender)
(define-data-var backup-admin principal tx-sender)

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
(define-constant ADMIN-RESTRICTED (err u313))
(define-constant DATA-ERROR (err u314))
(define-constant DATE-INVALID (err u315))

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
        handling-notes: (string-ascii 500),
        distribution-history: (list 10 {
            facility: (string-ascii 100),
            amount: uint,
            date: uint
        })
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
        license-expiry: uint,
        specialization: (string-ascii 50),
        patients-assigned: (list 100 (string-ascii 32)),
        performance-metrics: {
            treatments-given: uint,
            success-rate: uint,
            patient-feedback: uint
        }
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
        }),
        staff-count: uint,
        equipment-status: (list 10 {
            equipment-id: (string-ascii 32),
            status: (string-ascii 20),
            last-maintenance: uint
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

;; Administrative Functions
(define-public (update-admin (new-admin principal))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (validate-user new-admin) DATA-ERROR)
        (ok (var-set network-admin new-admin))
    )
)

;; Patient Management
(define-public (register-patient
    (patient-id (string-ascii 32)))
    (begin
        (asserts! (verify-provider-status tx-sender) UNAUTHORIZED)
        (asserts! (is-none (map-get? patient-records {patient-id: patient-id})) DUPLICATE-PATIENT)
        (ok (map-set patient-records
            {patient-id: patient-id}
            {
                treatment-history: (list),
                completed-treatments: u0,
                adverse-reactions: (list),
                medical-exemption: none
            }))
    )
)

(define-public (record-treatment
    (patient-id (string-ascii 32))
    (treatment {
        package-used: (string-ascii 32),
        medicine-given: (string-ascii 50),
        dose-number: uint,
        facility-name: (string-ascii 100),
        followup-date: (optional uint)
    }))
    (begin
        (asserts! (verify-provider-status tx-sender) UNAUTHORIZED)
        (match (map-get? patient-records {patient-id: patient-id})
            record (ok (map-set patient-records
                {patient-id: patient-id}
                (merge record {
                    treatment-history: (unwrap! 
                        (as-max-len? 
                            (concat 
                                (get treatment-history record)
                                (list {
                                    package-used: (get package-used treatment),
                                    treatment-date: TIMESTAMP,
                                    medicine-given: (get medicine-given treatment),
                                    dose-number: (get dose-number treatment),
                                    medical-provider: tx-sender,
                                    facility-name: (get facility-name treatment),
                                    followup-date: (get followup-date treatment)
                                }))
                            u10)
                        DATA-ERROR)
                })))
            INVALID-PATIENT)
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
        storage-location: (string-ascii 100),
        handling-notes: (string-ascii 500)
    }))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (is-none (map-get? inventory-tracker {package-id: package-id})) DUPLICATE-PACKAGE)
        (ok (map-set inventory-tracker 
            {package-id: package-id}
            (merge details {
                package-state: "active",
                temp-violations: u0,
                distribution-history: (list)
            })))
    )
)

;; Query Functions
(define-read-only (get-patient-history (patient-id (string-ascii 32)))
    (map-get? patient-records {patient-id: patient-id})
)

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