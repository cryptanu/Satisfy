// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICredentialAdapter {
    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        view
        returns (bool);
}
