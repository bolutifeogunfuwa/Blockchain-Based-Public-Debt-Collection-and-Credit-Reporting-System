;; Credit Reporting Accuracy Contract
;; Monitors credit bureaus and ensures accurate reporting

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-REPORT-NOT-FOUND (err u301))
(define-constant ERR-INVALID-SCORE (err u302))
(define-constant ERR-BUREAU-NOT-REGISTERED (err u303))
(define-constant ERR-DISPUTE-EXISTS (err u304))

;; Data Variables
(define-data-var next-report-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var min-credit-score uint u300)
(define-data-var max-credit-score uint u850)

;; Data Maps
(define-map credit-reports
  { report-id: uint }
  {
    consumer-principal: principal,
    bureau-principal: principal,
    credit-score: uint,
    report-date: uint,
    accuracy-verified: bool,
    verification-date: (optional uint),
    disputed: bool
  }
)

(define-map credit-bureaus
  { bureau-principal: principal }
  {
    bureau-name: (string-ascii 50),
    registration-date: uint,
    accuracy-rating: uint,
    total-reports: uint,
    disputed-reports: uint,
    active: bool
  }
)

(define-map accuracy-disputes
  { dispute-id: uint }
  {
    report-id: uint,
    consumer-principal: principal,
    bureau-principal: principal,
    dispute-reason: (string-ascii 200),
    dispute-date: uint,
    resolution-date: (optional uint),
    resolved: bool,
    outcome: (optional (string-ascii 100))
  }
)

(define-map consumer-credit-history
  { consumer-principal: principal, entry-id: uint }
  {
    report-id: uint,
    previous-score: (optional uint),
    new-score: uint,
    change-reason: (string-ascii 100),
    date: uint
  }
)

;; Read-only functions
(define-read-only (get-credit-report (report-id uint))
  (map-get? credit-reports { report-id: report-id })
)

(define-read-only (get-credit-bureau (bureau-principal principal))
  (map-get? credit-bureaus { bureau-principal: bureau-principal })
)

(define-read-only (get-accuracy-dispute (dispute-id uint))
  (map-get? accuracy-disputes { dispute-id: dispute-id })
)

(define-read-only (is-bureau-registered (bureau-principal principal))
  (match (get-credit-bureau bureau-principal)
    bureau-data (get active bureau-data)
    false
  )
)

(define-read-only (get-bureau-accuracy-rating (bureau-principal principal))
  (match (get-credit-bureau bureau-principal)
    bureau-data (some (get accuracy-rating bureau-data))
    none
  )
)

(define-read-only (is-valid-credit-score (score uint))
  (and
    (>= score (var-get min-credit-score))
    (<= score (var-get max-credit-score))
  )
)

;; Public functions
(define-public (register-credit-bureau (bureau-name (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (get-credit-bureau tx-sender)) ERR-BUREAU-NOT-REGISTERED)

    (map-set credit-bureaus
      { bureau-principal: tx-sender }
      {
        bureau-name: bureau-name,
        registration-date: block-height,
        accuracy-rating: u100,
        total-reports: u0,
        disputed-reports: u0,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (submit-credit-report
  (consumer-principal principal)
  (credit-score uint)
)
  (let
    (
      (report-id (var-get next-report-id))
      (bureau-data (unwrap! (get-credit-bureau tx-sender) ERR-BUREAU-NOT-REGISTERED))
    )
    (asserts! (get active bureau-data) ERR-BUREAU-NOT-REGISTERED)
    (asserts! (is-valid-credit-score credit-score) ERR-INVALID-SCORE)

    (map-set credit-reports
      { report-id: report-id }
      {
        consumer-principal: consumer-principal,
        bureau-principal: tx-sender,
        credit-score: credit-score,
        report-date: block-height,
        accuracy-verified: false,
        verification-date: none,
        disputed: false
      }
    )

    (map-set credit-bureaus
      { bureau-principal: tx-sender }
      (merge bureau-data { total-reports: (+ (get total-reports bureau-data) u1) })
    )

    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

(define-public (verify-report-accuracy (report-id uint))
  (let
    (
      (report-data (unwrap! (get-credit-report report-id) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set credit-reports
      { report-id: report-id }
      (merge report-data
        {
          accuracy-verified: true,
          verification-date: (some block-height)
        }
      )
    )
    (ok true)
  )
)

(define-public (dispute-credit-report
  (report-id uint)
  (dispute-reason (string-ascii 200))
)
  (let
    (
      (report-data (unwrap! (get-credit-report report-id) ERR-REPORT-NOT-FOUND))
      (dispute-id (var-get next-dispute-id))
      (bureau-data (unwrap! (get-credit-bureau (get bureau-principal report-data)) ERR-BUREAU-NOT-REGISTERED))
    )
    (asserts! (is-eq tx-sender (get consumer-principal report-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get disputed report-data)) ERR-DISPUTE-EXISTS)

    (map-set accuracy-disputes
      { dispute-id: dispute-id }
      {
        report-id: report-id,
        consumer-principal: tx-sender,
        bureau-principal: (get bureau-principal report-data),
        dispute-reason: dispute-reason,
        dispute-date: block-height,
        resolution-date: none,
        resolved: false,
        outcome: none
      }
    )

    (map-set credit-reports
      { report-id: report-id }
      (merge report-data { disputed: true })
    )

    (map-set credit-bureaus
      { bureau-principal: (get bureau-principal report-data) }
      (merge bureau-data { disputed-reports: (+ (get disputed-reports bureau-data) u1) })
    )

    (var-set next-dispute-id (+ dispute-id u1))
    (ok dispute-id)
  )
)

(define-public (resolve-dispute
  (dispute-id uint)
  (outcome (string-ascii 100))
  (score-correction (optional uint))
)
  (let
    (
      (dispute-data (unwrap! (get-accuracy-dispute dispute-id) ERR-REPORT-NOT-FOUND))
      (report-data (unwrap! (get-credit-report (get report-id dispute-data)) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (get resolved dispute-data)) ERR-DISPUTE-EXISTS)

    (map-set accuracy-disputes
      { dispute-id: dispute-id }
      (merge dispute-data
        {
          resolved: true,
          resolution-date: (some block-height),
          outcome: (some outcome)
        }
      )
    )

    (match score-correction
      corrected-score
        (begin
          (asserts! (is-valid-credit-score corrected-score) ERR-INVALID-SCORE)
          (map-set credit-reports
            { report-id: (get report-id dispute-data) }
            (merge report-data { credit-score: corrected-score, disputed: false })
          )
        )
      (map-set credit-reports
        { report-id: (get report-id dispute-data) }
        (merge report-data { disputed: false })
      )
    )

    (ok true)
  )
)

(define-public (update-bureau-accuracy-rating (bureau-principal principal) (new-rating uint))
  (let
    (
      (bureau-data (unwrap! (get-credit-bureau bureau-principal) ERR-BUREAU-NOT-REGISTERED))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rating u100) ERR-INVALID-SCORE)

    (map-set credit-bureaus
      { bureau-principal: bureau-principal }
      (merge bureau-data { accuracy-rating: new-rating })
    )
    (ok true)
  )
)
