// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISelfAttestationRegistry {
    struct AttestationRecord {
        address subject;
        uint8 age;
        bool contributor;
        bool daoMember;
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 context;
        bool revoked;
        bool exists;
    }

    function getAttestation(bytes32 attestationId) external view returns (AttestationRecord memory);
}
