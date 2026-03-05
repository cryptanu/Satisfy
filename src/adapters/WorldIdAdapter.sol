// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../interfaces/ICredentialAdapter.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {Ownable} from "../utils/Ownable.sol";

contract WorldIdAdapter is ICredentialAdapter, Ownable {
    using ECDSA for bytes32;

    struct WorldProof {
        bool human;
        uint64 expiresAt;
        bytes signature;
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
        WorldProof memory proof = abi.decode(proofPayload, (WorldProof));

        bool requireHuman = true;
        if (policyCondition.length > 0) {
            requireHuman = abi.decode(policyCondition, (bool));
        }

        if (requireHuman && !proof.human) return false;
        if (proof.expiresAt < block.timestamp) return false;

        bytes32 digest = keccak256(abi.encodePacked("SATISFY_WORLD_ID_V1", user, proof.human, proof.expiresAt))
            .toEthSignedMessageHash();

        return digest.recover(proof.signature) == issuer;
    }
}
