# Remaining Production Gaps

This repository now includes production-shaped verifier adapters, bridged attestation registry, role-gated automation, and timelock administration support.

## Still Required Before Mainnet Launch

- Wire `WorldIdAdapter` to audited canonical verifier addresses for each target chain.
- Replace relay mock operation with hardened relay service (HSM-backed keys, signer quorum, monitoring, incident runbooks).
- Run external smart-contract security audit and resolve findings.
- Add formal verification/property tests for replay, role isolation, and pause guarantees.
- Implement operational observability:
  - on-chain event indexing
  - alerting on signer churn, policy churn, replay failures
- Define governance SOPs:
  - timelock delay policy
  - emergency procedure and rollback policy
  - role rotation cadence

## CI/Fixture Security Notes

- Real-data fixture secret (`REALDATA_FIXTURE_JSON_B64`) must be scoped to protected branches.
- Fixture generation should remove any unnecessary PII and keep only cryptographic payload fields.
- Rotate relay/test signer material periodically even for testnet lanes.
