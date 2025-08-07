;; Debt Validation Verification Contract
;; Requires collectors to provide proof of debt ownership

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-DEBT-NOT-FOUND (err u401))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-VALIDATION-EXISTS (err u403))
(define-constant ERR-INSUFFICIENT-PROOF (err u404))

;; Data Variables
(define-data-var next-debt-id uint u1)
(define-data-var next-validation-id uint u1)
(define-data-var validation-period uint u2016) ;; ~2 weeks in blocks

;; Data Maps
(define-map debt-records
  { debt-id: uint }
  {
    debtor-principal: principal,
    collector-principal: principal,
    original-creditor: (string-ascii 100),
    debt-amount: uint,
    creation-date: uint,
    validation-status: (string-ascii 20),
    validation-deadline: uint,
    validated: bool
  }
)

(define-map validation-requests
  { validation-id: uint }
  {
    debt-id: uint,
    debtor-principal: principal,
    request-date: uint,
    response-deadline: uint,
    responded: bool,
    valid-debt: bool
  }
)

(define-map debt-proofs
  { debt-id: uint }
  {
    proof-type: (string-ascii 50),
    document-hash: (buff 32),
    submission-date: uint,
    verified: bool,
    verifier-principal: (optional principal)
  }
)

(define-map ownership-chain
  { debt-id: uint, transfer-id: uint }
  {
    from-creditor: (string-ascii 100),
    to-collector: principal,
    transfer-date: uint,
    transfer-amount: uint,
    documentation-hash: (buff 32)
  }
)

;; Read-only functions
(define-read-only (get-debt-record (debt-id uint))
  (map-get? debt-records { debt-id: debt-id })
)

(define-read-only (get-validation-request (validation-id uint))
  (map-get? validation-requests { validation-id: validation-id })
)

(define-read-only (get-debt-proof (debt-id uint))
  (map-get? debt-proofs { debt-id: debt-id })
)

(define-read-only (is-debt-validated (debt-id uint))
  (match (get-debt-record debt-id)
    debt-data (get validated debt-data)
    false
  )
)

(define-read-only (is-validation-expired (debt-id uint))
  (match (get-debt-record debt-id)
    debt-data (> block-height (get validation-deadline debt-data))
    true
  )
)

(define-read-only (get-ownership-transfer (debt-id uint) (transfer-id uint))
  (map-get? ownership-chain { debt-id: debt-id, transfer-id: transfer-id })
)

;; Public functions
(define-public (register-debt
  (debtor-principal principal)
  (original-creditor (string-ascii 100))
  (debt-amount uint)
)
  (let
    (
      (debt-id (var-get next-debt-id))
      (deadline (+ block-height (var-get validation-period)))
    )
    (asserts! (> debt-amount u0) ERR-INVALID-AMOUNT)

    (map-set debt-records
      { debt-id: debt-id }
      {
        debtor-principal: debtor-principal,
        collector-principal: tx-sender,
        original-creditor: original-creditor,
        debt-amount: debt-amount,
        creation-date: block-height,
        validation-status: "pending",
        validation-deadline: deadline,
        validated: false
      }
    )

    (var-set next-debt-id (+ debt-id u1))
    (ok debt-id)
  )
)

(define-public (submit-debt-proof
  (debt-id uint)
  (proof-type (string-ascii 50))
  (document-hash (buff 32))
)
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get collector-principal debt-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-validation-expired debt-id)) ERR-VALIDATION-EXISTS)

    (map-set debt-proofs
      { debt-id: debt-id }
      {
        proof-type: proof-type,
        document-hash: document-hash,
        submission-date: block-height,
        verified: false,
        verifier-principal: none
      }
    )
    (ok true)
  )
)

(define-public (request-debt-validation (debt-id uint))
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
      (validation-id (var-get next-validation-id))
      (response-deadline (+ block-height (var-get validation-period)))
    )
    (asserts! (is-eq tx-sender (get debtor-principal debt-data)) ERR-NOT-AUTHORIZED)

    (map-set validation-requests
      { validation-id: validation-id }
      {
        debt-id: debt-id,
        debtor-principal: tx-sender,
        request-date: block-height,
        response-deadline: response-deadline,
        responded: false,
        valid-debt: false
      }
    )

    (var-set next-validation-id (+ validation-id u1))
    (ok validation-id)
  )
)

(define-public (verify-debt-proof (debt-id uint))
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
      (proof-data (unwrap! (get-debt-proof debt-id) ERR-INSUFFICIENT-PROOF))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set debt-proofs
      { debt-id: debt-id }
      (merge proof-data
        {
          verified: true,
          verifier-principal: (some tx-sender)
        }
      )
    )

    (map-set debt-records
      { debt-id: debt-id }
      (merge debt-data
        {
          validated: true,
          validation-status: "validated"
        }
      )
    )
    (ok true)
  )
)

(define-public (record-ownership-transfer
  (debt-id uint)
  (transfer-id uint)
  (from-creditor (string-ascii 100))
  (transfer-amount uint)
  (documentation-hash (buff 32))
)
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get collector-principal debt-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> transfer-amount u0) ERR-INVALID-AMOUNT)

    (map-set ownership-chain
      { debt-id: debt-id, transfer-id: transfer-id }
      {
        from-creditor: from-creditor,
        to-collector: tx-sender,
        transfer-date: block-height,
        transfer-amount: transfer-amount,
        documentation-hash: documentation-hash
      }
    )
    (ok true)
  )
)

(define-public (invalidate-debt (debt-id uint) (reason (string-ascii 100)))
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set debt-records
      { debt-id: debt-id }
      (merge debt-data
        {
          validated: false,
          validation-status: "invalid"
        }
      )
    )
    (ok true)
  )
)

(define-public (update-debt-amount (debt-id uint) (new-amount uint))
  (let
    (
      (debt-data (unwrap! (get-debt-record debt-id) ERR-DEBT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get collector-principal debt-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> new-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (get validated debt-data)) ERR-VALIDATION-EXISTS)

    (map-set debt-records
      { debt-id: debt-id }
      (merge debt-data { debt-amount: new-amount })
    )
    (ok true)
  )
)

(define-public (set-validation-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set validation-period new-period)
    (ok true)
  )
)
