;; Medical Supply Chain Management - Stage 3
;; Added emergency protocols and batch processing

;; Core Administrator Setup
(define-data-var network-admin principal tx-sender)
(define-data-var backup-admin principal tx-sender)
(define-data-var emergency-mode bool false)

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
(define-constant EMERGENCY-ONLY (err u317))
(define-constant BATCH-ERROR (err u318))
(define-constant PRIORITY-ERROR (err u319))
(define-constant THRESHOLD-EXCEEDED (err u320))

;; Operational Parameters
(define-constant STORAGE-MIN-TEMP (- 75))
(define-constant STORAGE-MAX-TEMP 5)
(define-constant INTERVAL-REQUIRED u28)
(define-constant MAX-TREATMENT-SERIES u4)
(define-constant MINIMUM-LENGTH u1)
(define-constant TIMESTAMP block-height)
(define-constant MAX-PRIORITY-LEVEL u5)
(define-constant EMERGENCY-THRESHOLD u100)
(define-constant BATCH-SIZE u50)

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
        priority-level: uint,
        batch-number: (string-ascii 32),
        quality-checks: (list 5 {
            inspector: principal,
            check-date: uint,
            status: (string-ascii 20)
        }),
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
        medical-exemption: (optional (string-ascii 200)),
        priority-status: uint,
        emergency-contact: (string-ascii 100),
        allergies: (list 5 (string-ascii 50)),
        treatment-plan: (optional {
            start-date: uint,
            end-date: uint,
            notes: (string-ascii 500)
        })
    }
)

(define-map provider-directory 
    principal 
    {
        role: (string-ascii 20),
        facility-name: (string-ascii 100),
        license-expiry: uint,
        specialization: (string-ascii 50),
        certification-level: uint,
        emergency-authorized: bool,
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
        emergency-capacity: uint,
        staff-count: uint,
        equipment-status: (list 10 {
            equipment-id: (string-ascii 32),
            status: (string-ascii 20),
            last-maintenance: uint
        }),
        supply-alerts: (list 10 {
            item: (string-ascii 50),
            threshold: uint,
            current-level: uint
        }),
        operation-hours: {
            weekday-start: uint,
            weekday-end: uint,
            weekend-available: bool
        }
    }
)

(define-map batch-registry
    { batch-id: (string-ascii 32) }
    {
        packages: (list 50 (string-ascii 32)),
        creation-date: uint,
        status: (string-ascii 20),
        quality-score: uint
    }
)

(define-map distribution-queue
    uint
    {
        facility: (string-ascii 100),
        package-id: (string-ascii 32),
        amount: uint,
        priority: uint,
        requested-date: uint
    }
)

;; Utility Functions
(define-private (is-network-admin)
    (is-eq tx-sender (var-get network-admin))
)

(define-private (is-emergency-authorized)
    (and 
        (var-get emergency-mode)
        (match (map-get? provider-directory tx-sender)
            provider (get emergency-authorized provider)
            false)
    )
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

;; Emergency Management Functions
(define-public (activate-emergency-mode)
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (ok (var-set emergency-mode true))
    )
)

(define-public (deactivate-emergency-mode)
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (ok (var-set emergency-mode false))
    )
)

(define-public (register-emergency-provider
    (provider principal)
    (certification-level uint))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (match (map-get? provider-directory provider)
            details (ok (map-set provider-directory
                provider
                (merge details {
                    emergency-authorized: true,
                    certification-level: certification-level
                })))
            UNAUTHORIZED)
    )
)

;; Batch Processing Functions
(define-public (register-batch 
    (batch-id (string-ascii 32)) 
    (packages (list 50 (string-ascii 32))))
    (begin
        (asserts! (is-network-admin) ADMIN-RESTRICTED)
        (asserts! (>= (len packages) BATCH-SIZE) BATCH-ERROR)
        (ok (map-set batch-registry 
            { batch-id: batch-id }
            {
                packages: packages,
                creation-date: TIMESTAMP,
                status: "pending",
                quality-score: u0
            }))
    )
)

(define-public (process-batch 
    (batch-id (string-ascii 32))
    (quality-score uint))
    (begin
        (asserts! (or (is-network-admin) (is-emergency-authorized)) UNAUTHORIZED)
        (match (map-get? batch-registry {batch-id: batch-id})
            batch (ok (map-set batch-registry
                {batch-id: batch-id}
                (merge batch {
                    status: "processed",
                    quality-score: quality-score
                })))
            BATCH-ERROR)
    )
)

;; Priority Management Functions
(define-public (update-patient-priority 
    (patient-id (string-ascii 32)) 
    (new-priority uint))
    (begin
        (asserts! (or (is-network-admin) (is-emergency-authorized)) UNAUTHORIZED)
        (asserts! (<= new-priority MAX-PRIORITY-LEVEL) PRIORITY-ERROR)
        (match (map-get? patient-records {patient-id: patient-id})
            record (ok (map-set patient-records 
                {patient-id: patient-id}
                (merge record {priority-status: new-priority})))
            INVALID-PATIENT)
    )
)

;; Supply Chain Functions
(define-public (request-emergency-supplies
    (facility-id (string-ascii 100))
    (package-id (string-ascii 32))
    (amount uint))
    (begin
        (asserts! (var-get emergency-mode) EMERGENCY-ONLY)
        (asserts! (<= amount EMERGENCY-THRESHOLD) THRESHOLD-EXCEEDED)
        (match (map-get? facility-registry facility-id)
            facility (ok (map-set distribution-queue
                TIMESTAMP
                {
                    facility: facility-id,
                    package-id: package-id,
                    amount: amount,
                    priority: u1,
                    requested-date: TIMESTAMP
                }))
            FACILITY-INVALID)
    )
)

(define-public (process-distribution-request
    (request-id uint))
    (begin
        (asserts! (or (is-network-admin) (is-emergency-authorized)) UNAUTHORIZED)
        (match (map-get? distribution-queue request-id)
            request (begin
                (asserts! (is-some (map-get? facility-registry (get facility request))) FACILITY-INVALID)
                (asserts! (is-some (map-get? inventory-tracker {package-id: (get package-id request)})) INVALID-PACKAGE)
                (ok (map-delete distribution-queue request-id)))
            DATA-ERROR)
    )
)

;; Enhanced Query Functions
(define-read-only (get-facility-supply-status (facility-id (string-ascii 100)))
    (match (map-get? facility-registry facility-id)
        facility (ok {
            current-stock: (get current-stock facility),
            alerts: (get supply-alerts facility),
            emergency-capacity: (get emergency-capacity facility)
        })
        FACILITY-INVALID)
)

(define-read-only (get-provider-performance (provider principal))
    (match (map-get? provider-directory provider)
        details (ok (get performance-metrics details))
        UNAUTHORIZED)
)

(define-read-only (check-batch-status (batch-id (string-ascii 32)))
    (map-get? batch-registry {batch-id: batch-id})
)

(define-read-only (get-emergency-queue)
    (match (map-get? distribution-queue TIMESTAMP)
        request (ok request)
        (err MISSING-PACKAGE))
)

;; System Status Functions
(define-read-only (get-emergency-status)
    (ok (var-get emergency-mode))
)

(define-read-only (verify-emergency-authorization (provider principal))
    (match (map-get? provider-directory provider)
        details (ok (get emergency-authorized details))
        (err UNAUTHORIZED))
)