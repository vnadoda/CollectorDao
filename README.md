# Collector DAO
The aim of collector DAO is to buy valuable NFTs based on member proposals.
The DAO supports following features:
- Anyone can become a member of the DAO by paying `1 ETH` membership fee
- Member can create a proposal to buy NFT(s) from any NFT marketplace
- Members can vote on a proposal only once
- Any member can execute the passed proposal to buy the NFT(s) per the proposal
- The DAO governance contract also provides `EIP-712` compliant API to process a single or a batch of offline votes

## Voting System Design

Following is a voting mechanism for proposals to buy NFTs.

1) A member creates the proposal. Proposal can have at most 5 actions specified.
2) There is no voting delay and all members can start voting immediately
3) Voting for a proposal will last for 1 day after proposal is created
4) A member can cast vote `Against` or `For` proposal or can `Abstain`.
   <br> a) Each member will have vote weight based on membership age. **`1 day of membership = 1 vote weight`**. Minimum vote weight is 1.
   <br> b) For quorum requirements, member vote without weight will be used.
   <br> c) To meet quorum, at least 5 or 25% or more of all members have to vote by voting period ends
5) After end of voting period, no one can vote anymore. 
   Proposal is deemed passed if quorum has reached & total for votes are greater or equal to against votes,
   otherwise a proposal is deemed defeated.
   <br> Abstained votes are only used for quorum requirements.
6) If a proposal has been passed, then any member can execute the proposal.
   <br> No delay after proposal is passed, immediate execution.
7) `Passed` proposal will be considered `expired` if it is not executed successfully or was not executed at all within 2 days after creation
   
## Design considerations, risks & trade-offs:
- No voting delay: 
  <br> For NFTs price can move fast, so having no delay is better.
  <br> Tradeoff: members may miss the vote because of urgency

- Voting period is 1 day:
  <br> If proposal doesn't pass in a day, it is considered defeated
  <br> For NFTs price can move fast, quick decision is better.
  <br> Tradeoff: members may miss the vote because of urgency

- Voting weight is based on membership age:
  <br> Members accrue 1 vote per each day of membership. This gives more weight to longtime DAO members.
  <br> Tradeoff: this may cause membership decline over time. One other option would be to cap the vote weight after some time.

- Members can have many proposals at a time:
  This implementation doesn't restrict member with max proposals or total max at a time.
  <br> Tradeoff: there is potential for denial of service attack by flooding the proposal system. 
  <br>One deterrent is the cost to create proposals

- Block.number for timing instead of block.timestamp:
  <br> `block.number` would have better guard against the time manipulation.
  
## Following are voting mechanism options I have considered:
   1) 1 member 1 vote with same weight
      <br> There is no incentive for long term participation
   2) New member can't propose until 5 days after becoming member
      <br> This may provide some deterrent to flooding the system with proposals
   3) Governance token based voting power
      <br> This may be the better solution, but main problem is complexities involved. It also increases attack surface area.

## Implementation
This project uses following technologies & tools:
- `Solidity` for smart contract development
- `Hardhat` for local ethereum network & running tests
- `JavaScript, Ethers, Waffle/Chai` for unit testing
- `ESLint, Prettier & Solhint` for code styling
- `solidity-coverage` for code coverage

## Testing Contract
1. Clone repo using `git`
2. Run `npm install` from project directory
3. Open terminal & run tests : `npx hardhat test`