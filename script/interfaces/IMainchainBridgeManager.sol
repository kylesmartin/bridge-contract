// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ContractType } from "@ronin/contracts/utils/ContractType.sol";
import { RoleAccess } from "@ronin/contracts/utils/RoleAccess.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { GlobalProposal } from "@ronin/contracts/libraries/GlobalProposal.sol";
import { VoteStatusConsumer } from "@ronin/contracts/interfaces/consumers/VoteStatusConsumer.sol";
import { SignatureConsumer } from "@ronin/contracts/interfaces/consumers/SignatureConsumer.sol";
import { Ballot } from "@ronin/contracts/libraries/Ballot.sol";

interface IMainchainBridgeManager is VoteStatusConsumer, SignatureConsumer {
  error ErrBelowMinRequiredGovernors();
  error ErrContractTypeNotFound(ContractType contractType);
  error ErrCurrentProposalIsNotCompleted();
  error ErrDuplicated(bytes4 msgSig);
  error ErrExistOneInternalCallFailed(address sender, bytes4 msgSig, bytes callData);
  error ErrGovernorNotFound(address governor);
  error ErrGovernorNotMatch(address required, address sender);
  error ErrInsufficientGas(bytes32 proposalHash);
  error ErrInvalidArguments(bytes4 msgSig);
  error ErrInvalidChainId(bytes4 msgSig, uint256 actual, uint256 expected);
  error ErrInvalidExpiryTimestamp();
  error ErrInvalidInput();
  error ErrInvalidOrder(bytes4 msgSig);
  error ErrInvalidProposalNonce(bytes4 msgSig);
  error ErrInvalidThreshold(bytes4 msgSig);
  error ErrInvalidVoteWeight(bytes4 msgSig);
  error ErrLengthMismatch(bytes4 msgSig);
  error ErrLooseProposalInternallyRevert(uint256 callIndex, bytes revertMsg);
  error ErrNonExecutorCannotRelay(address executor, address caller);
  error ErrOnlySelfCall(bytes4 msgSig);
  error ErrOperatorNotFound(address operator);
  error ErrRelayFailed(bytes4 msgSig);
  error ErrUnauthorized(bytes4 msgSig, RoleAccess expectedRole);
  error ErrUnsupportedInterface(bytes4 interfaceId, address addr);
  error ErrUnsupportedVoteType(bytes4 msgSig);
  error ErrVoteIsFinalized();
  error ErrZeroAddress(bytes4 msgSig);
  error ErrZeroCodeContract(address addr);

  event BridgeOperatorAddingFailed(address indexed operator);
  event BridgeOperatorRemovingFailed(address indexed operator);
  event BridgeOperatorUpdated(address indexed governor, address indexed fromBridgeOperator, address indexed toBridgeOperator);
  event BridgeOperatorsAdded(bool[] statuses, uint96[] voteWeights, address[] governors, address[] bridgeOperators);
  event BridgeOperatorsRemoved(bool[] statuses, address[] bridgeOperators);
  event CallbackRegistered(address, bool);
  event ContractUpdated(ContractType indexed contractType, address indexed addr);
  event GlobalProposalCreated(
    uint256 indexed round,
    bytes32 indexed proposalHash,
    Proposal.ProposalDetail proposal,
    bytes32 globalProposalHash,
    GlobalProposal.GlobalProposalDetail globalProposal,
    address creator
  );
  event Initialized(uint8 version);
  event MinRequiredGovernorUpdated(uint256 min);
  event Notified(bytes callData, address[] registers, bool[] statuses, bytes[] returnDatas);
  event ProposalApproved(bytes32 indexed proposalHash);
  event ProposalCreated(uint256 indexed chainId, uint256 indexed round, bytes32 indexed proposalHash, Proposal.ProposalDetail proposal, address creator);
  event ProposalExecuted(bytes32 indexed proposalHash, bool[] successCalls, bytes[] returnDatas);
  event ProposalExpired(bytes32 indexed proposalHash);
  event ProposalExpiryDurationChanged(uint256 indexed duration);
  event ProposalRejected(bytes32 indexed proposalHash);
  event ProposalVoted(bytes32 indexed proposalHash, address indexed voter, Ballot.VoteType support, uint256 weight);
  event TargetOptionUpdated(GlobalProposal.TargetOption indexed targetOption, address indexed addr);
  event ThresholdUpdated(uint256 indexed nonce, uint256 indexed numerator, uint256 indexed denominator, uint256 previousNumerator, uint256 previousDenominator);

  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function addBridgeOperators(uint96[] memory voteWeights, address[] memory governors, address[] memory bridgeOperators) external;
  function checkThreshold(uint256 voteWeight) external view returns (bool);
  function getBridgeOperatorWeight(address bridgeOperator) external view returns (uint96 weight);
  function getBridgeOperators() external view returns (address[] memory);
  function getCallbackRegisters() external view returns (address[] memory registers);
  function getContract(ContractType contractType) external view returns (address contract_);
  function getFullBridgeOperatorInfos() external view returns (address[] memory governors, address[] memory bridgeOperators, uint96[] memory weights);
  function getGovernorOf(address operator) external view returns (address governor);
  function getGovernorWeight(address governor) external view returns (uint96 weight);
  function getGovernorWeights(address[] memory governors) external view returns (uint96[] memory weights);
  function getGovernors() external view returns (address[] memory);
  function getOperatorOf(address governor) external view returns (address operator);
  function getProposalExpiryDuration() external view returns (uint256);
  function getThreshold() external view returns (uint256 num, uint256 denom);
  function getTotalWeight() external view returns (uint256);
  function globalProposalRelayed(uint256 _round) external view returns (bool);
  function initialize(
    uint256 num,
    uint256 denom,
    uint256 roninChainId,
    address bridgeContract,
    address[] memory callbackRegisters,
    address[] memory bridgeOperators,
    address[] memory governors,
    uint96[] memory voteWeights,
    GlobalProposal.TargetOption[] memory targetOptions,
    address[] memory targets
  ) external;
  function isBridgeOperator(address addr) external view returns (bool);
  function minimumVoteWeight() external view returns (uint256);
  function registerCallbacks(address[] memory registers) external;
  function relayGlobalProposal(
    GlobalProposal.GlobalProposalDetail memory globalProposal,
    Ballot.VoteType[] memory supports_,
    Signature[] memory signatures
  ) external;
  function relayProposal(Proposal.ProposalDetail memory proposal, Ballot.VoteType[] memory supports_, Signature[] memory signatures) external;
  function removeBridgeOperators(address[] memory bridgeOperators) external;
  function resolveTargets(GlobalProposal.TargetOption[] memory targetOptions) external view returns (address[] memory targets);
  function round(uint256) external view returns (uint256);
  function setContract(ContractType contractType, address addr) external;
  function setMinRequiredGovernor(uint256 min) external;
  function setThreshold(uint256 num, uint256 denom) external;
  function sumGovernorsWeight(address[] memory governors) external view returns (uint256 sum);
  function totalBridgeOperator() external view returns (uint256);
  function unregisterCallbacks(address[] memory registers) external;
  function updateManyTargetOption(GlobalProposal.TargetOption[] memory targetOptions, address[] memory targets) external;
  function vote(
    uint256,
    uint256
  ) external view returns (VoteStatus status, bytes32 hash, uint256 againstVoteWeight, uint256 forVoteWeight, uint256 expiryTimestamp);
}
