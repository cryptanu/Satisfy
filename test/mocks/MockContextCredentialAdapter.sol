// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../../src/interfaces/ICredentialAdapter.sol";
import {ICredentialAdapterV2} from "../../src/interfaces/ICredentialAdapterV2.sol";

contract MockContextCredentialAdapter is ICredentialAdapter, ICredentialAdapterV2 {
    function verify(address, bytes calldata, bytes calldata) external pure override returns (bool) {
        return false;
    }

    function verifyWithContext(
        address user,
        bytes calldata proofPayload,
        bytes calldata policyCondition,
        bytes32 bundleNullifier,
        uint64 epoch,
        uint256 policyId
    ) external pure override returns (bool) {
        (bytes32 proofTag, address proofUser, bytes32 expectedNullifier, uint64 expectedEpoch, uint256 expectedPolicyId) =
            abi.decode(proofPayload, (bytes32, address, bytes32, uint64, uint256));
        bytes32 expectedTag = abi.decode(policyCondition, (bytes32));

        return proofTag == expectedTag && proofUser == user && expectedNullifier == bundleNullifier
            && expectedEpoch == epoch && expectedPolicyId == policyId;
    }
}
