// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICredentialAdapterV2 {
    function verifyWithContext(
        address user,
        bytes calldata proofPayload,
        bytes calldata policyCondition,
        bytes32 bundleNullifier,
        uint64 epoch,
        uint256 policyId
    ) external view returns (bool);
}
