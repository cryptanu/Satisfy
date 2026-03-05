// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyTypes} from "../types/SatisfyTypes.sol";

interface IPolicyEngine {
    function satisfies(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        external
        view
        returns (bool);

    function validateAndConsume(uint256 policyId, address user, SatisfyTypes.ProofBundle calldata bundle)
        external
        returns (bool);
}
