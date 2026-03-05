// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../interfaces/ICredentialAdapter.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {Ownable} from "../utils/Ownable.sol";

contract SelfAdapter is ICredentialAdapter, Ownable {
    using ECDSA for bytes32;

    struct SelfProof {
        uint8 age;
        bool contributor;
        bool daoMember;
        uint64 expiresAt;
        bytes signature;
    }

    struct SelfCondition {
        uint8 minAge;
        bool requireContributor;
        bool requireDaoMember;
    }

    address public issuer;

    error InvalidIssuer();

    event IssuerUpdated(address indexed oldIssuer, address indexed newIssuer);

    constructor(address initialOwner, address initialIssuer) Ownable(initialOwner) {
        if (initialIssuer == address(0)) revert InvalidIssuer();
        issuer = initialIssuer;
        emit IssuerUpdated(address(0), initialIssuer);
    }

    function setIssuer(address newIssuer) external onlyOwner {
        if (newIssuer == address(0)) revert InvalidIssuer();
        address oldIssuer = issuer;
        issuer = newIssuer;
        emit IssuerUpdated(oldIssuer, newIssuer);
    }

    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        view
        override
        returns (bool)
    {
        SelfProof memory proof = abi.decode(proofPayload, (SelfProof));

        SelfCondition memory condition;
        if (policyCondition.length > 0) {
            condition = abi.decode(policyCondition, (SelfCondition));
        }

        if (proof.expiresAt < block.timestamp) return false;
        if (proof.age < condition.minAge) return false;
        if (condition.requireContributor && !proof.contributor) return false;
        if (condition.requireDaoMember && !proof.daoMember) return false;

        bytes32 digest = keccak256(
                abi.encodePacked(
                    "SATISFY_SELF_V1", user, proof.age, proof.contributor, proof.daoMember, proof.expiresAt
                )
            ).toEthSignedMessageHash();

        return digest.recover(proof.signature) == issuer;
    }
}
