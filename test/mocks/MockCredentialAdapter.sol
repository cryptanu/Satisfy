// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICredentialAdapter} from "../../src/interfaces/ICredentialAdapter.sol";

contract MockCredentialAdapter is ICredentialAdapter {
    function verify(address user, bytes calldata proofPayload, bytes calldata policyCondition)
        external
        pure
        override
        returns (bool)
    {
        (bytes32 proofTag, address proofUser) = abi.decode(proofPayload, (bytes32, address));
        bytes32 expectedTag = abi.decode(policyCondition, (bytes32));
        return proofTag == expectedTag && proofUser == user;
    }
}
