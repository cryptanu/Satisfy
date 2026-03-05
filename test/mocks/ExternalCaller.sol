// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SatisfyHook} from "../../src/SatisfyHook.sol";
import {SatisfyPolicyEngine} from "../../src/SatisfyPolicyEngine.sol";
import {SatisfyTypes} from "../../src/types/SatisfyTypes.sol";

contract ExternalCaller {
    function callSetEpoch(SatisfyPolicyEngine engine, uint64 epoch) external returns (bool success) {
        (success,) = address(engine).call(abi.encodeWithSelector(engine.setEpoch.selector, epoch));
    }

    function callSetPoolPolicy(SatisfyHook hook, bytes32 poolId, uint256 policyId) external returns (bool success) {
        (success,) = address(hook).call(abi.encodeWithSelector(hook.setPoolPolicy.selector, poolId, policyId));
    }

    function callBeforeSwap(SatisfyHook hook, bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle)
        external
        returns (bool success)
    {
        (success,) = address(hook).call(abi.encodeWithSelector(hook.beforeSwap.selector, poolId, sender, bundle));
    }

    function callValidateAndConsume(
        SatisfyPolicyEngine engine,
        uint256 policyId,
        address user,
        SatisfyTypes.ProofBundle calldata bundle
    ) external returns (bool success) {
        (success,) = address(engine)
            .call(abi.encodeWithSelector(engine.validateAndConsume.selector, policyId, user, bundle));
    }
}
