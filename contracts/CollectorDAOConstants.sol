// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

/**
 * @notice CollectorDAO constants/structs/events
 */
abstract contract CollectorDAOConstants {
    /// @notice EIP-712 compliant domain seperator type hash
    bytes32 public constant DOMAIN_TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice EIP-712 compliant ballot type hash
    bytes32 public constant BALLOT_TYPE_HASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    /// @notice name of this contract
    string public constant CONTRACT_NAME = "CollectorDAO";

    /// @notice version of this contract
    string public constant CONTRACT_VERSION = "1.0";

    /// @notice 1 ETH membership fee
    uint public constant MEMBERSHIP_FEE = 1 ether;
    
    /// @notice percentage of total members who need to vote to reach quorum
    uint public constant QUORUM_PERCENTAGE = 25;
    
    /// @notice At most 5 actions/operations can be included in any Proposal
    uint public constant PROPOSAL_MAX_ACTION_COUNT = 5;

    /// @notice Proposal will be active for 1 day for member to cast votes.
    ///         After a day, votes will be counted to detrmine the result (Succeeded or Defeated)
    uint public constant VOTING_PERIOD_IN_DAYS = 1 days;

    /// @notice Proposal will be considered expired after creation time + 2 days.
    uint public constant PROPOSAL_EXPIRY_IN_DAYS = 2 days;

    /// @notice Signature for function "buyNft"
    string public constant BUY_NFT_FUNC_SIGNATURE = "buyNft(address,address,unit,uint)";

    /// @notice Possible vote types members can use
    enum VoteType {
        Against, For, Abstain
    }

    /// @notice a single vote for a proposal
    struct Vote {
        /// @notice a flag to track wheather vote is casted or not
        bool casted;

        /// @notice member's vote
        VoteType voteType;

        /// @notice member's vote weight calculated at the time of voting based on membership age in days
        uint voteWeight;
    }

    /// @notice A struct to represent proposal
    struct Proposal {
        /// @notice creator of the proposal
        address proposer;

        /// @notice timetsamp of proposal creation
        uint creationTime;

        /// @notice total number of votes in favor of this proposal
        uint forVotes;

        /// @notice total number of votes against this proposal
        uint againstVotes;

        /// @notice total number of abstain votes
        uint abstainVotes;

        /// @notice total number of members who have voted
        uint memberVoteCount;

        /// @notice specifies whether proposal execution is successful or not
        bool success;

        /// @notice mapping to track members' votes for this proposal
        mapping (address => Vote) votes;
    }

    /// @notice various state of proposal
    enum ProposalState {
        /// @notice a proposal does not exist yet
        None,

        /// @notice a proposal is under vote
        Active,

        /// @notice a proposal has reached quorum requirements but voting is still under progress
        QuorumReached,

        /// @notice a proposal has reached quorum requirements and have majority for votes after voting ended
        Passed,

        /// @notice a proposal either has not reached quorum requirements or doesn't have majority FOR votes after voting ended
        Defeated,

        /// @notice a proposal is passed and successfully executed
        Succeeded,

        /// @notice a proposal could not be executed or was not executed within 2 days of its creation
        Expired
    }

    /// @dev Event emitted upon proposal execution
    event MemberJoined(address member, uint startDate);

    /// @dev Event emitted upon proposal creation
    event ProposalCreated(
        uint indexed proposalId, 
        address proposer,
        address[] targets, 
        uint[] values,
        bytes[] calldatas,
        string description,
        uint creationTime
    );

    /// @dev Event emitted upon casting a vote
    event VoteCasted(uint indexed proposalId, address member, VoteType voteType, uint voteWeight);

    /// @dev Event emitted upon proposal execution
    event ProposalExecuted(uint indexed proposalId);
}