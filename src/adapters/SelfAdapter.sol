// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../interfaces/ICredentialAdapter.sol";
import {ISelfAttestationRegistry} from "../interfaces/ISelfAttestationRegistry.sol";
import {Ownable} from "../utils/Ownable.sol";

contract SelfAdapter is ICredentialAdapter, Ownable {
    struct SelfAttestationProofV1 {
        bytes32 attestationId;
        bytes32 context;
    }

    struct SelfConditionV1 {
        uint8 minAge;
        bool requireContributor;
        bool requireDaoMember;
        uint64 maxAttestationAge;
    }

    ISelfAttestationRegistry public registry;

    error InvalidRegistry();

    event RegistryUpdated(address indexed previousRegistry, address indexed newRegistry);

    constructor(address initialOwner, address initialRegistry) Ownable(initialOwner) {
        if (initialRegistry == address(0)) revert InvalidRegistry();
        registry = ISelfAttestationRegistry(initialRegistry);
        emit RegistryUpdated(address(0), initialRegistry);
    }

    function setRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert InvalidRegistry();
        address oldRegistry = address(registry);
        registry = ISelfAttestationRegistry(newRegistry);
        emit RegistryUpdated(oldRegistry, newRegistry);
    }

    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        view
        override
        returns (bool)
    {
        SelfAttestationProofV1 memory proof = abi.decode(proofPayload, (SelfAttestationProofV1));

        SelfConditionV1 memory condition;
        if (policyCondition.length > 0) {
            condition = abi.decode(policyCondition, (SelfConditionV1));
        }

        bytes32 expectedContext = keccak256(abi.encodePacked(block.chainid, address(this), user, policyCondition));
        if (proof.context != expectedContext) return false;

        ISelfAttestationRegistry.AttestationRecord memory record = registry.getAttestation(proof.attestationId);
        if (!record.exists) return false;
        if (record.revoked) return false;
        if (record.subject != user) return false;
        if (record.context != proof.context) return false;
        if (record.expiresAt < block.timestamp) return false;
        if (record.issuedAt > block.timestamp) return false;
        if (
            condition.maxAttestationAge != 0
                && block.timestamp > uint256(record.issuedAt) + uint256(condition.maxAttestationAge)
        ) {
            return false;
        }

        if (record.age < condition.minAge) return false;
        if (condition.requireContributor && !record.contributor) return false;
        if (condition.requireDaoMember && !record.daoMember) return false;

        return true;
    }
}
