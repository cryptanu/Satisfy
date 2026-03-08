// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IWorldIdVerifier} from "../interfaces/IWorldIdVerifier.sol";

contract MockWorldIdVerifier is IWorldIdVerifier {
    mapping(bytes32 => bool) public validProof;

    error InvalidProof();

    function setValidProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof,
        bool allowed
    ) external {
        bytes32 key = _proofKey(root, groupId, signalHash, nullifierHash, externalNullifierHash, proof);
        validProof[key] = allowed;
    }

    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view {
        bytes32 key = _proofKey(root, groupId, signalHash, nullifierHash, externalNullifierHash, proof);
        if (!validProof[key]) revert InvalidProof();
    }

    function _proofKey(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(root, groupId, signalHash, nullifierHash, externalNullifierHash, proof));
    }
}
