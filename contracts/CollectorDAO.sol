// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import "./INftMarketPlace.sol";
import "./CollectorDAOConstants.sol";

/**
 * @notice DAO to buy valuable NFTs based on membership proposals!
 */
contract CollectorDAO is CollectorDAOConstants {
    /// @notice address of this contract
    address public immutable contractAddress;

    /// @notice total number of members in the DAO
    uint public totalMemberCount;

    /// @notice structured data hash for this doman
    bytes32 private _domainHash;

    /// @notice A mapping to track members and their membership age, 
    /// time since they have joined the DAO
    mapping (address => uint) public members;
    
    /// @notice All proposals in the system mapped by id (hash of actions data)
    mapping(uint => Proposal) private _proposals;

    constructor() {
        contractAddress = address(this);
        _domainHash = keccak256(abi.encode(DOMAIN_TYPE_HASH, keccak256(bytes(CONTRACT_NAME)), keccak256(bytes(CONTRACT_VERSION)), block.chainid, contractAddress));
    }

    /// @notice a modifier to specify on member only functions
    modifier onlyMember() {
        _verifyMembership(msg.sender);
        _;
    }

    /**
     * @notice Anyone can be a member for 1 ETH
     */
    function becomeMember() external payable {
        require(msg.value == MEMBERSHIP_FEE, "Requires 1 ETH Membership fee");
        require(members[msg.sender] == 0, "Already member");

        uint startDate = block.timestamp;
        members[msg.sender] = startDate;
        totalMemberCount++;

        emit MemberJoined(msg.sender, startDate);
    }

    /**
     * @notice Provides a generic way to create 
     * a proposal with arbitrary number of actions with required calldatas
     */
    function propose(
        address[] memory targets, 
        uint[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public onlyMember {
        _verifyProposalData(targets, values, calldatas);

        uint proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        Proposal storage proposal = _proposals[proposalId];
        require(proposal.creationTime == 0, "Proposal already exist");
        
        proposal.proposer = msg.sender;
        proposal.creationTime = block.timestamp;

        emit ProposalCreated(proposalId, msg.sender, targets, values, calldatas, description, proposal.creationTime);
    }

    /**
     * @notice Creates a proposal to buy specified NFT using the specified marketplace
     */
    function proposeNftToBuy(address nftMarketPlaceAddress, address nftContract, uint nftId, uint proposedPrice, string calldata description) external onlyMember {
        /// Prepare args to call contract's propose method
        address[] memory targets = new address[](1);
        targets[0] = contractAddress;

        uint[] memory values = new uint[](1);
        values[0] = proposedPrice;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(BUY_NFT_FUNC_SIGNATURE, nftMarketPlaceAddress, nftContract, nftId, proposedPrice);

        propose(targets, values, calldatas, description);
    }

    /**
     * @notice A member can cast vote(for/against/abstain) on a proposal with specified id.
     */
    function castVote(uint proposalId, VoteType voteType) external onlyMember {
        _castVote(msg.sender, proposalId, voteType);
    }

    /**
     * @notice A member can cast vote(for/against/abstain) on a proposal using signature.
     * @dev EIP-712 compliant external function to cast a vote using a collected signature.
     */
    function castVoteBySignature(uint proposalId, uint8 voteType, uint8 v, bytes32 r, bytes32 s) external {
        _castVoteBySignature(proposalId, voteType, v, r, s);
    }

    /**
     * @notice Batch function to cast vote(for/against/abstain) on a proposals using signatures.
     * @dev EIP-712 compliant external function to cast votes using collected signatures in a batch.
     *      length of all arrays must be same.
     */
    function castVoteBySignatureBatch(
        uint[] calldata proposalIds,
        uint8[] calldata voteTypes,
        uint8[] calldata vs,
        bytes32[] calldata rs, 
        bytes32[] calldata ss
    ) external {
        require(proposalIds.length > 0, "Proposal votes empty");
        require(proposalIds.length == voteTypes.length, "Invalid proposal votes length");
        require(voteTypes.length == vs.length, "Invalid proposal votes length");
        require(vs.length == rs.length, "Invalid proposal votes length");
        require(rs.length == ss.length, "Invalid proposal votes length");

        for (uint256 index = 0; index < proposalIds.length; index++) {
            _castVoteBySignature(proposalIds[index], voteTypes[index], vs[index], rs[index], ss[index]);
        }
    }

    /**
     * @notice Executes a passed proposal.
     *         Action data arrays (targets, values, calldatas) needs to exactly match with what was provided with the proposal.
     */
    function execute(
        address[] memory targets, 
        uint[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external onlyMember {
        _verifyProposalData(targets, values, calldatas);

        /// Ensure that the proposal state is "Passed"
        uint proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState state = determineState(proposalId);
        require(state == ProposalState.Passed, "Proposal not passed");

        /// Verify that total value is less than or equal to contract's balance
        uint totalValue;
        for (uint256 i = 0; i < values.length; i++) {
            totalValue += values[i];
        }
        require(totalValue <= address(this).balance, "Insufficient funds");

        _proposals[proposalId].success = true;

        /// Execute the proposal
        for (uint256 index = 0; index < targets.length; index++) {
            (bool success,) = targets[index].call{value: values[index]}(calldatas[index]);
            require(success, "Proposal execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @dev External function to be executed only via proposal system
     */
    function buyNft(address nftMarketPlaceAddress, address nftContract, uint nftId, uint proposedPrice) external payable {
        require(msg.sender == contractAddress, "Can't buy NFT externally");
        require(proposedPrice <= contractAddress.balance, "Insufficient funds");

        INftMarketPlace nftMarketPlace = INftMarketPlace(nftMarketPlaceAddress);
        uint price = nftMarketPlace.getPrice(nftContract, nftId);
        require(price <= proposedPrice, "NFT price increased");

        require(nftMarketPlace.buy{value: price}(nftContract, nftId), "Failed to buy NFT");
    }

    /**
     * @notice provides a member vote for a proposal with specified id.
     */
    function getMemberVote(uint proposalId) external view returns(Vote memory) {
        return _proposals[proposalId].votes[msg.sender];
    }

    /**
     * @notice provides current vote counts for a proposal with specified id.
     */
    function getProposalVotes(uint proposalId) external view returns(uint forVotes, uint againstVotes, uint abstainVotes, uint memberVoteCount) {
        Proposal storage proposal = _proposals[proposalId];
        return (proposal.forVotes, proposal.againstVotes, proposal.abstainVotes, proposal.memberVoteCount);
    }

    /**
     * @notice Determines the state of the proposal with specified id.
     * @dev see ProposalState enum comments for requirements of each state.
     */
    function determineState(uint proposalId) public view returns(ProposalState) {
        Proposal storage proposal = _proposals[proposalId];
        return _determineState(proposal);
    }

    /**
     * Private function to handle common proposal state
     */
    function _determineState(Proposal storage proposal) private view returns(ProposalState) {
        uint creationTime = proposal.creationTime;

        if(creationTime == 0) {
            /// proposal does not exist
            return ProposalState.None;
        }

        if (proposal.success) {
            /// proposal has been successfuly executed (all specified actions were completed)
            return ProposalState.Succeeded;
        }

        /// check for proposal expiration
        if (block.timestamp >= (creationTime + PROPOSAL_EXPIRY_IN_DAYS)) {
            return ProposalState.Expired;
        }

        if (_hasQuorumReached(proposal.memberVoteCount)) {
            /// Voting period is ended, count the votes
            if (block.timestamp >= (creationTime + VOTING_PERIOD_IN_DAYS)) {
                return proposal.forVotes >= proposal.againstVotes ? ProposalState.Passed : ProposalState.Defeated;
            }
            else {
                return ProposalState.QuorumReached;
            }
        }

        return ProposalState.Active;
    }

    /**
     * @dev a common private function to handle public castVoteBySignature & castVoteBySignatureBatch functions
     */
    function _castVoteBySignature(uint proposalId, uint8 voteType, uint8 v, bytes32 r, bytes32 s) private {
        bytes32 ballot = keccak256(abi.encode(BALLOT_TYPE_HASH, proposalId, voteType));
        bytes32 typedMessage = keccak256(abi.encodePacked("\x19\x01", _domainHash, ballot));
        address signer = ecrecover(typedMessage, v, r, s);

        _castVote(signer, proposalId, VoteType(voteType));
    }

    /**
     * @dev a common private function to handle public castVote, castVoteBySignature & castVoteBySignatureBatch functions
     */
    function _castVote(address member, uint proposalId, VoteType voteType) private {
        _verifyMembership(member);

        /// Ensure that state is either Active or QuorumReached
        Proposal storage proposal = _proposals[proposalId];
        ProposalState state = _determineState(proposal);
        require(state == ProposalState.Active || state == ProposalState.QuorumReached, "Proposal is not active");

        Vote storage memberVote = proposal.votes[member];

        require(memberVote.casted == false, "Member already voted");

        uint voteWeight;
        if (voteType == VoteType.Abstain) {
            /// Abstainee vote doesn't have any weight, 
            /// it is just tracked for a record
            proposal.abstainVotes++;
        }
        else {
            voteWeight = getMemberVoteWeight(member);
            if (voteType == VoteType.Against) {
                proposal.againstVotes += voteWeight;
            }

            if (voteType == VoteType.For) {
                proposal.forVotes += voteWeight;
            }
        }

        memberVote.casted = true;
        memberVote.voteType = voteType;
        memberVote.voteWeight = voteWeight;
        
        /// Track member vote count & total votes for this proposal
        proposal.memberVoteCount++;

        emit VoteCasted(proposalId, member, voteType, voteWeight);
    }

    /**
     * @dev This function is used to produce proposal id.
     */
    function hashProposal (
        address[] memory targets, 
        uint[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) private pure returns(uint) {
        return uint(keccak256((abi.encode(targets, values, calldatas, descriptionHash))));
    }

    /**
     * @dev Calculates member's vote weight based membership age in days.
     * Each day of membership accrues 1 vote weight.
     * Vote weight will not be counted for Quorum requirements.
     */
    function getMemberVoteWeight(address member) private view returns (uint) {
        uint voteWeight = (block.timestamp - members[member]) / 60 / 60 / 24;
        return voteWeight > 0 ? voteWeight : 1;
    }

    function _verifyMembership(address member) private view {
        require(members[member] > 0, "Not a member");
    }

    function _verifyProposalData(
        address[] memory targets, 
        uint[] memory values,
        bytes[] memory calldatas
    ) private pure {
        require(targets.length > 0, "Empty proposal");
        require(targets.length <= PROPOSAL_MAX_ACTION_COUNT, "Too many actions");
        require(targets.length == values.length, "Invalid proposal length");
        require(values.length == calldatas.length, "Invalid proposal length");
    }

    /**
     * @dev Determines whether "quorum" has been reached. 
     * i.e atleast 5 or 25% or more of all members have voted.
     */
    function _hasQuorumReached(uint memberVoteCount) private view returns(bool) {
        uint quorumCount = ((totalMemberCount * QUORUM_PERCENTAGE) / 100);
        return memberVoteCount >= 5 && memberVoteCount >= quorumCount;
    }
}