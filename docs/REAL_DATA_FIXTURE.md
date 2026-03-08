# Real-Data Fixture Format

`script/ci_real_data_replay.sh` accepts either individual env vars or a base64-encoded JSON fixture in `REALDATA_FIXTURE_JSON_B64`.

## JSON Schema

```json
{
  "user": "0x...",
  "worldCondition": "0x...",
  "worldProofPayload": "0x...",
  "selfCondition": "0x...",
  "selfAttestationPayload": "0x...",
  "selfAttestationSignature": "0x...",
  "selfProofPayload": "0x..."
}
```

All `0x...` values must be ABI-encoded bytes.

## Required Encodings

- `worldCondition`:
  - `abi.encode(WorldConditionV1)`
  - tuple shape: `(bool requireHuman, bytes32 externalNullifier, bytes32 policyContext, uint64 maxProofAge)`
- `worldProofPayload`:
  - `abi.encode(WorldIdProofV1)`
  - tuple shape: `(uint256 root, uint256 nullifierHash, uint256[8] proof, uint64 issuedAt, uint64 validUntil, bytes32 signal, bytes32 externalNullifier)`
- `selfCondition`:
  - `abi.encode(SelfConditionV1)`
  - tuple shape: `(uint8 minAge, bool requireContributor, bool requireDaoMember, uint64 maxAttestationAge, uint64 requiredSourceChainId, bytes32 requiredSourceBridgeId)`
- `selfAttestationPayload`:
  - `abi.encode(AttestationPayloadV1)`
  - tuple shape: `(bytes32 attestationId, address subject, uint8 age, bool contributor, bool daoMember, uint64 issuedAt, uint64 expiresAt, bytes32 context, uint64 sourceChainId, bytes32 sourceBridgeId, bytes32 sourceTxHash, uint32 sourceLogIndex, uint256 nonce)`
- `selfAttestationSignature`:
  - signature over `SelfAttestationRegistry.attestationDigest(payload)`
  - sign digest as raw hash (`cast wallet sign --no-hash`)
- `selfProofPayload`:
  - `abi.encode(SelfAttestationProofV1)`
  - tuple shape: `(bytes32 attestationId, bytes32 context)`

## Security Notes

- Keep fixtures in CI secrets, not in git history.
- Strip any non-essential PII before encoding.
- Rotate signer keys used for test relays.

## Build Helper

To generate fixture JSON and base64 secret value from env vars:

```bash
./script/build_realdata_fixture.sh
```

This prints a ready-to-paste `REALDATA_FIXTURE_JSON_B64=...` line for CI secrets.
