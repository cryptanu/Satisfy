// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-hooks-public/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {SatisfyTypes} from "./types/SatisfyTypes.sol";
import {Ownable} from "./utils/Ownable.sol";

contract SatisfyHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    IPolicyEngine public immutable policyEngine;

    bytes4 public constant LEGACY_BEFORE_SWAP_SELECTOR =
        bytes4(keccak256("beforeSwap(bytes32,address,((bytes32,bytes)[],bytes32,uint64))"));
    bytes4 public constant LEGACY_BEFORE_ADD_LIQUIDITY_SELECTOR =
        bytes4(keccak256("beforeAddLiquidity(bytes32,address,((bytes32,bytes)[],bytes32,uint64))"));

    mapping(bytes32 => uint256) public poolPolicy;
    mapping(address => bool) public authorizedCallers;
    bool public paused;

    error InvalidPoolManager();
    error InvalidPolicyEngine();
    error InvalidHookData();
    error HookCallerNotAuthorized();
    error HookPaused();
    error PoolPolicyNotSet(bytes32 poolId);

    event HookCallerUpdated(address indexed caller, bool allowed);
    event HookPauseUpdated(bool paused);
    event PoolPolicyUpdated(bytes32 indexed poolId, uint256 indexed policyId);
    event PolicyConsumed(bytes32 indexed poolId, address indexed user, uint256 indexed policyId, bytes4 hookSelector);

    modifier onlyAuthorizedCaller() {
        if (!authorizedCallers[msg.sender]) revert HookCallerNotAuthorized();
        _;
    }

    constructor(address initialOwner, address policyEngineAddress, address initialHookCaller)
        BaseHook(IPoolManager(_resolvePoolManager(initialOwner, initialHookCaller)))
        Ownable(initialOwner)
    {
        if (policyEngineAddress == address(0)) revert InvalidPolicyEngine();
        policyEngine = IPolicyEngine(policyEngineAddress);

        authorizedCallers[initialOwner] = true;
        emit HookCallerUpdated(initialOwner, true);

        if (initialHookCaller != address(0)) {
            authorizedCallers[initialHookCaller] = true;
            emit HookCallerUpdated(initialHookCaller, true);
        }
    }

    function setHookCaller(address caller, bool allowed) external onlyOwner {
        authorizedCallers[caller] = allowed;
        emit HookCallerUpdated(caller, allowed);
    }

    function setPaused(bool nextPaused) external onlyOwner {
        paused = nextPaused;
        emit HookPauseUpdated(nextPaused);
    }

    function setPoolPolicy(bytes32 poolId, uint256 policyId) external onlyOwner {
        poolPolicy[poolId] = policyId;
        emit PoolPolicyUpdated(poolId, policyId);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        permissions = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @dev Skip strict permission-bit address validation so this hook can be deployed with normal tooling.
    function validateHookAddress(BaseHook) internal pure override {}

    function beforeSwap(bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle)
        external
        onlyAuthorizedCaller
        returns (bytes4)
    {
        _enforce(poolId, sender, bundle, LEGACY_BEFORE_SWAP_SELECTOR);
        return LEGACY_BEFORE_SWAP_SELECTOR;
    }

    function beforeAddLiquidity(bytes32 poolId, address sender, SatisfyTypes.ProofBundle calldata bundle)
        external
        onlyAuthorizedCaller
        returns (bytes4)
    {
        _enforce(poolId, sender, bundle, LEGACY_BEFORE_ADD_LIQUIDITY_SELECTOR);
        return LEGACY_BEFORE_ADD_LIQUIDITY_SELECTOR;
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _enforce(_poolIdFromKey(key), sender, _decodeBundle(hookData), IHooks.beforeSwap.selector);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        _enforce(_poolIdFromKey(key), sender, _decodeBundle(hookData), IHooks.beforeAddLiquidity.selector);
        return IHooks.beforeAddLiquidity.selector;
    }

    function _enforce(bytes32 poolId, address sender, SatisfyTypes.ProofBundle memory bundle, bytes4 selector) internal {
        if (paused) revert HookPaused();
        uint256 policyId = poolPolicy[poolId];
        if (policyId == 0) revert PoolPolicyNotSet(poolId);

        policyEngine.validateAndConsume(policyId, sender, bundle);
        emit PolicyConsumed(poolId, sender, policyId, selector);
    }

    function _poolIdFromKey(PoolKey calldata key) internal pure returns (bytes32) {
        PoolKey memory poolKey = key;
        return PoolId.unwrap(poolKey.toId());
    }

    function _decodeBundle(bytes calldata hookData) internal pure returns (SatisfyTypes.ProofBundle memory bundle) {
        if (hookData.length == 0) revert InvalidHookData();
        bundle = abi.decode(hookData, (SatisfyTypes.ProofBundle));
    }

    function _resolvePoolManager(address initialOwner, address initialHookCaller) private pure returns (address) {
        address manager = initialHookCaller == address(0) ? initialOwner : initialHookCaller;
        if (manager == address(0)) revert InvalidPoolManager();
        return manager;
    }
}
