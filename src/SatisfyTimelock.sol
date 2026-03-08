// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./utils/Ownable.sol";

contract SatisfyTimelock is Ownable {
    uint64 public minDelay;

    mapping(address => bool) public proposers;
    mapping(address => bool) public executors;
    mapping(bytes32 => uint64) public operationReadyAt;

    error InvalidAddress();
    error InvalidDelay();
    error NotProposer();
    error NotExecutor();
    error OperationAlreadyScheduled(bytes32 operationId);
    error OperationNotScheduled(bytes32 operationId);
    error OperationNotReady(bytes32 operationId, uint64 readyAt, uint64 nowTs);
    error TimelockExecutionFailed(bytes data);

    event MinDelayUpdated(uint64 previousDelay, uint64 newDelay);
    event ProposerUpdated(address indexed proposer, bool allowed);
    event ExecutorUpdated(address indexed executor, bool allowed);
    event OperationScheduled(
        bytes32 indexed operationId,
        address indexed target,
        uint256 value,
        bytes data,
        bytes32 salt,
        uint64 executeAfter
    );
    event OperationCancelled(bytes32 indexed operationId);
    event OperationExecuted(bytes32 indexed operationId, address indexed target, uint256 value, bytes data);

    modifier onlyProposer() {
        if (!proposers[msg.sender]) revert NotProposer();
        _;
    }

    modifier onlyExecutor() {
        if (!executors[msg.sender]) revert NotExecutor();
        _;
    }

    constructor(
        address initialOwner,
        uint64 initialMinDelay,
        address initialProposer,
        address initialExecutor
    ) Ownable(initialOwner) {
        if (initialProposer == address(0) || initialExecutor == address(0)) revert InvalidAddress();
        minDelay = initialMinDelay;
        proposers[initialProposer] = true;
        executors[initialExecutor] = true;

        emit MinDelayUpdated(0, initialMinDelay);
        emit ProposerUpdated(initialProposer, true);
        emit ExecutorUpdated(initialExecutor, true);
    }

    function setMinDelay(uint64 newDelay) external onlyOwner {
        uint64 oldDelay = minDelay;
        minDelay = newDelay;
        emit MinDelayUpdated(oldDelay, newDelay);
    }

    function setProposer(address proposer, bool allowed) external onlyOwner {
        if (proposer == address(0)) revert InvalidAddress();
        proposers[proposer] = allowed;
        emit ProposerUpdated(proposer, allowed);
    }

    function setExecutor(address executor, bool allowed) external onlyOwner {
        if (executor == address(0)) revert InvalidAddress();
        executors[executor] = allowed;
        emit ExecutorUpdated(executor, allowed);
    }

    function schedule(address target, uint256 value, bytes calldata data, bytes32 salt, uint64 delay)
        external
        onlyProposer
        returns (bytes32 operationId)
    {
        if (target == address(0)) revert InvalidAddress();
        if (delay < minDelay) revert InvalidDelay();

        operationId = _operationId(target, value, data, salt);
        if (operationReadyAt[operationId] != 0) revert OperationAlreadyScheduled(operationId);

        uint64 executeAfter = uint64(block.timestamp) + delay;
        operationReadyAt[operationId] = executeAfter;
        emit OperationScheduled(operationId, target, value, data, salt, executeAfter);
    }

    function cancel(bytes32 operationId) external onlyProposer {
        if (operationReadyAt[operationId] == 0) revert OperationNotScheduled(operationId);
        delete operationReadyAt[operationId];
        emit OperationCancelled(operationId);
    }

    function execute(address target, uint256 value, bytes calldata data, bytes32 salt)
        external
        payable
        onlyExecutor
        returns (bytes memory result)
    {
        bytes32 operationId = _operationId(target, value, data, salt);
        uint64 executeAfter = operationReadyAt[operationId];
        if (executeAfter == 0) revert OperationNotScheduled(operationId);
        if (block.timestamp < executeAfter) {
            revert OperationNotReady(operationId, executeAfter, uint64(block.timestamp));
        }

        delete operationReadyAt[operationId];
        (bool ok, bytes memory returned) = target.call{value: value}(data);
        if (!ok) revert TimelockExecutionFailed(returned);

        emit OperationExecuted(operationId, target, value, data);
        return returned;
    }

    function getOperationId(address target, uint256 value, bytes calldata data, bytes32 salt)
        external
        view
        returns (bytes32)
    {
        return _operationId(target, value, data, salt);
    }

    function _operationId(address target, uint256 value, bytes calldata data, bytes32 salt)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(block.chainid, address(this), target, value, data, salt));
    }
}
