const { expect } = require("chai");
const { ethers } = require("hardhat");

const parseEther = ethers.utils.parseEther;

describe("CollectorDAO", function () {
  let deployer;
  let member1;
  let member2;
  let accounts;

  let collectorDAO;
  let testNftMarketPlace;
  let domain;
  let ballotTypes;

  async function becomeMember(account) {
    await collectorDAO
      .connect(account)
      .becomeMember({ value: parseEther("1") });
  }

  beforeEach(async function () {
    [deployer, member1, member2, ...accounts] = await ethers.getSigners();

    const TestNftMarketPlaceFactory = await ethers.getContractFactory("TestNftMarketPlace");
    testNftMarketPlace = await TestNftMarketPlaceFactory.connect(deployer).deploy();
    await testNftMarketPlace.deployed();

    const CollectorDAOFactory = await ethers.getContractFactory("CollectorDAO");
    collectorDAO = await CollectorDAOFactory.connect(deployer).deploy();
    await collectorDAO.deployed();
    await becomeMember(member1);

    domain = {
      name: "CollectorDAO",
      version: "1.0",
      chainId: 31337,
      verifyingContract: collectorDAO.address,
    };

    // Ballot(uint256 proposalId,uint8 support)
    ballotTypes = {
      Ballot: [
        { name: "proposalId", type: "uint256" },
        { name: "support", type: "uint8" },
      ],
    };
  });

  describe("deployment", async function () {
    it("is deployed", async function () {
      expect(collectorDAO !== undefined).to.equal(true);
    });
  });

  describe("membership", async function () {
    it("should revert when fee is less than 1 ETH", async function () {
      await expect(
        collectorDAO
          .connect(member1)
          .becomeMember({ value: parseEther("0.99") })
      ).to.be.revertedWith("Requires 1 ETH Membership fee");
    });

    it("should revert when fee is greater than 1 ETH", async function () {
      await expect(
        collectorDAO.connect(member1).becomeMember({ value: parseEther("1.1") })
      ).to.be.revertedWith("Requires 1 ETH Membership fee");
    });

    it("should revert when account is already member", async function () {
      await expect(
        collectorDAO.connect(member1).becomeMember({ value: parseEther("1") })
      ).to.be.revertedWith("Already member");
    });

    it("should allow membership with 1 ETH fee", async function () {
      await becomeMember(member2);
      expect((await collectorDAO.members(member2.address)).gt(0)).to.equal(true);
    });
  });

  describe("buyNft", async function () {
    it("should revert when buyNft is called externally", async function () {
      await expect(
        collectorDAO
          .connect(member1)
          .buyNft(testNftMarketPlace.address, accounts[0].address, 1, parseEther("11"))
      ).to.be.revertedWith("Can't buy NFT externally");
    });
  });

  describe("propose", async function () {
    it("should revert when called by non-member", async function () {
      await expect(
        collectorDAO.connect(deployer).propose([], [], [], "test")
      ).to.be.revertedWith("Not a member");
    });

    it("should revert when targets array is empty", async function () {
      await expect(
        collectorDAO.connect(member1).propose([], [], [], "test")
      ).to.be.revertedWith("Empty proposal");
    });

    it("should revert when there are more than 5 actions", async function () {
      await expect(
        collectorDAO.connect(member1).propose(accounts.map(a => a.address), [], [], "test")
      ).to.be.revertedWith("Too many actions");
    });

    it("should revert when targets & values length don't match", async function () {
      await expect(
        collectorDAO
          .connect(member1)
          .propose([member1.address, member2.address], [1], [], "test")
      ).to.be.revertedWith("Invalid proposal length");
    });

    it("should revert when values & calldatas length don't match", async function () {
      await expect(
        collectorDAO
          .connect(member1)
          .propose(
            [member1.address, member2.address],
            [1, 2],
            [ethers.utils.defaultAbiCoder.encode(["string"], ["hello"])],
            "test"
          )
      ).to.be.revertedWith("Invalid proposal length");
    });

    it("should create a proposal with valid data", async function () {
      const event = await createProposal();
      expect(event.proposer).to.equal(member1.address);

      // verify proposal state to be active after creation
      expect(await collectorDAO.determineState(event.proposalId)).to.equal(1);
    });

    it("should revert on creating a same proposal again", async function () {
      await createProposal();

      await expect(createProposal()).to.be.revertedWith("Proposal already exist");
    });
  });

  describe("castVote", async function () {
    it("should revert when called by non-member", async function () {
      await expect(
        collectorDAO.connect(deployer).castVote(1, 0)
      ).to.be.revertedWith("Not a member");
    });

    it("should revert when called with non-existent proposal id", async function () {
      await expect(
        collectorDAO.connect(member1).castVote(1, 0)
      ).to.be.revertedWith("Proposal is not active");
    });

    it("should revert when proposal is expired", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // move forward 2 days
      await increaseTime(2);

      await expect(
        collectorDAO.connect(member1).castVote(proposalId, 0)
      ).to.be.revertedWith("Proposal is not active");
    });

    it("should revert when vote is casted again", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // vote against the proposal
      await collectorDAO.connect(member1).castVote(proposalId, 0);

      await expect(
        collectorDAO.connect(member1).castVote(proposalId, 1)
      ).to.be.revertedWith("Member already voted");
    });

    it("should accept the against vote for valid proposal", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // vote against the proposal
      await collectorDAO.connect(member1).castVote(proposalId, 0);

      // verify the vote & vote counts
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalId,
        expectedVoteType: 0,
        voteWeight: 1,
        forVotes: 0,
        againstVotes: 1,
        abstainVotes: 0,
        total: 1,
      });
    });

    it("should accept the for vote for valid proposal", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // vote for the proposal
      await collectorDAO.connect(member1).castVote(proposalId, 1);

      // verify the vote & vote counts
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalId,
        expectedVoteType: 1,
        voteWeight: 1,
        forVotes: 1,
        againstVotes: 0,
        abstainVotes: 0,
        total: 1,
      });
    });

    it("should accept the abstain vote for valid proposal", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // abstain  vote
      await collectorDAO.connect(member1).castVote(proposalId, 2);

      // verify the vote & vote counts
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalId,
        expectedVoteType: 2,
        voteWeight: 0,
        forVotes: 0,
        againstVotes: 0,
        abstainVotes: 1,
        total: 1,
      });
    });
  });

  describe("castVoteBySignature", async function () {
    it("should accept single vote with a signature", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // cast vote using sig
      const sig = await member1._signTypedData(domain, ballotTypes, { proposalId: proposalId, support: 1});
      const splitSig = ethers.utils.splitSignature(sig);
      await collectorDAO.connect(member1).castVoteBySignature(proposalId, 1, splitSig.v, splitSig.r, splitSig.s);

      // verify the vote & vote counts
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalId,
        expectedVoteType: 1,
        voteWeight: 1,
        forVotes: 1,
        againstVotes: 0,
        abstainVotes: 0,
        total: 1,
      });
    });
  });

  describe("castVoteBySignatureBatch", async function () {
    it("should revert when proposal array is empty", async function () {
      await expect(
        collectorDAO.connect(member1).castVoteBySignatureBatch([], [], [], [], [])
      ).to.be.revertedWith("Proposal votes empty");
    });

    it("should revert when proposal ids & vote types array length don't match", async function () {
      await expect(
        collectorDAO.connect(member1).castVoteBySignatureBatch([1], [], [], [], [])
      ).to.be.revertedWith("Invalid proposal votes length");
    });

    it("should revert when vote types & vs array length don't match", async function () {
      await expect(
        collectorDAO.connect(member1).castVoteBySignatureBatch([1], [1], [], [], [])
      ).to.be.revertedWith("Invalid proposal votes length");
    });

    it("should accept multiple votes for different proposals", async function () {
      const proposalIds = [];
      const supports = [];
      const vs = [];
      const rs = [];
      const ss = [];

      // single member casting 2 votes for 2 different proposals
      for (let index = 0; index < 2; index++) {
        // create a proposal
        const proposalId = (await createProposal("test" + index)).proposalId;
        proposalIds.push(proposalId);
        supports.push(index);

        const sig = await member1._signTypedData(domain, ballotTypes, { proposalId: proposalId, support: index});
        const splitSig = ethers.utils.splitSignature(sig);
        vs.push(splitSig.v);
        rs.push(splitSig.r);
        ss.push(splitSig.s);
      }

      await collectorDAO.connect(member1).castVoteBySignatureBatch(proposalIds, supports, vs, rs, ss);

      // verify the vote & vote counts for proposal 1
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalIds[0],
        expectedVoteType: 0,
        voteWeight: 1,
        forVotes: 0,
        againstVotes: 1,
        abstainVotes: 0,
        total: 1,
      });

      // verify the vote & vote counts for proposal 2
      await verifyMemberVoteAndTotalVoteCounts({
        member: member1,
        proposalId: proposalIds[1],
        expectedVoteType: 1,
        voteWeight: 1,
        forVotes: 1,
        againstVotes: 0,
        abstainVotes: 0,
        total: 1,
      });
    });

    it("should accept multiple votes from different members for same proposal", async function () {
      const proposalIds = [];
      const supports = [];
      const vs = [];
      const rs = [];
      const ss = [];

      // 2 members casting votes for same proposal
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      for (let index = 0; index < 2; index++) {
        proposalIds.push(proposalId);
        supports.push(index);

        await becomeMember(accounts[index]);

        const sig = await accounts[index]._signTypedData(domain, ballotTypes, { proposalId: proposalId, support: index});
        const splitSig = ethers.utils.splitSignature(sig);
        vs.push(splitSig.v);
        rs.push(splitSig.r);
        ss.push(splitSig.s);
      }

      await collectorDAO.castVoteBySignatureBatch(proposalIds, supports, vs, rs, ss);

      // verify both member votes
      await verifyMemberVote({
        member: accounts[0],
        proposalId: proposalId,
        expectedVoteType: 0,
        voteWeight: 1,
      });
      await verifyMemberVote({
        member: accounts[1],
        proposalId: proposalId,
        expectedVoteType: 1,
        voteWeight: 1,
      });

      await verifyTotalVoteCounts({
        proposalId: proposalId,
        forVotes: 1,
        againstVotes: 1,
        abstainVotes: 0,
        total: 2,
      });
    });
  });

  describe("scenario: creation -> voted -> passed -> executed", async function () {
    it("should succeed", async function () {
      // create a proposal
      const proposalId = (await createProposal()).proposalId;

      // make 10 members and cast votes
      for (let index = 0; index < 10; index++) {
        const account = accounts[index];
        // make an account a member
        await becomeMember(account);

        // vote for or against/abstain  the proposal
        const expectedVoteType = index < 2 ? 2 : (index < 5 ? 0 : 1);
        await collectorDAO.connect(account).castVote(proposalId, expectedVoteType);
        await verifyMemberVote({member: account, proposalId: proposalId, expectedVoteType: expectedVoteType, voteWeight: expectedVoteType == 2 ? 0 : 1}); 
      }

      // verify the total vote counts, total 10 = 2 abstain, 3 against & 5 for
      await verifyTotalVoteCounts({
        proposalId: proposalId,
        forVotes: 5,
        againstVotes: 3,
        abstainVotes: 2,
        total: 10,
      });

      // total 10/10 votes, so verify proposal state to be QuorumReached
      expect(await collectorDAO.determineState(proposalId)).to.equal(2);

      await expect(collectorDAO.connect(member1)
        .execute([collectorDAO.address], [1], [createBuyNftCalldata()], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test")))
      ).to.be.revertedWith("Proposal not passed");

      // Move time forward by 1 days
      await increaseTime(1);

      // total 10 = 2 abstain, 3 against & 5 for, so verify proposal state to be Passed
      expect(await collectorDAO.determineState(proposalId)).to.equal(3);

      // casting vote at this state should fail
      await expect(
        collectorDAO.connect(member1).castVote(proposalId, 0)
      ).to.be.revertedWith("Proposal is not active");

      // now execute the proposal
      await collectorDAO
        .connect(member1)
        .execute([collectorDAO.address], [1], [createBuyNftCalldata()], ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test")));

      // Verify proposal state to be succeeded
      expect(await collectorDAO.determineState(proposalId)).to.equal(5);

      // casting vote at this state should fail
      await expect(
        collectorDAO.connect(member1).castVote(proposalId, 0)
      ).to.be.revertedWith("Proposal is not active");
    });
  });

  describe("proposeNftToBuy", async function () {
    it("should revert when called by non-member", async function () {
      await expect(
        collectorDAO.connect(deployer).proposeNftToBuy(testNftMarketPlace.address, testNftMarketPlace.address, 1, parseEther("1"), "test")
      ).to.be.revertedWith("Not a member");
    });

    it("should create a new proposal", async function () {
      const tx = await collectorDAO.connect(member1).proposeNftToBuy(testNftMarketPlace.address, testNftMarketPlace.address, 1, parseEther("1"), "test");
      const event = (await getEvents(tx))[0].args;

      // verify that proposal is created
      expect(event.proposer).to.equal(member1.address);
      expect(await collectorDAO.determineState(event.proposalId)).to.equal(1);
    });
  });

  async function increaseTime(days) {
    await network.provider.send("evm_increaseTime", [60 * 60 * 24 * days]);
    // Need to mine block after increasing time
    await network.provider.send("evm_mine", []);
  }

  async function createProposal(description = "test") {
    const tx = await collectorDAO
      .connect(member1)
      .propose([collectorDAO.address], [1], [createBuyNftCalldata()], description);
    const event = (await getEvents(tx))[0].args;
    return event;
  }

  async function getEvents(tx) {
    const receipt = await tx.wait();
    return receipt.events;
  }

  function createBuyNftCalldata() {
    return new ethers.utils.Interface([
      "function buyNft(address nftMarketPlaceAddress, address nftContract, uint nftId, uint proposedPrice)",
    ]).encodeFunctionData("buyNft", [
      testNftMarketPlace.address,
      testNftMarketPlace.address, // not important
      1,
      parseEther("1"),
    ]);
  }

  async function verifyMemberVoteAndTotalVoteCounts(obj) {
    await verifyMemberVote(obj);
    await verifyTotalVoteCounts(obj);
  }

  async function verifyMemberVote(obj) {
    const vote = await collectorDAO.connect(obj.member).getMemberVote(obj.proposalId);
    expect(vote.casted).to.equal(true);
    expect(vote.voteType).to.equal(obj.expectedVoteType);
    expect(vote.voteWeight).to.equal(obj.voteWeight);
  }

  async function verifyTotalVoteCounts(obj) {
    const voteCounts = await collectorDAO.getProposalVotes(obj.proposalId);
    // console.log(voteCounts);
    expect(voteCounts.forVotes).to.equal(obj.forVotes);
    expect(voteCounts.againstVotes).to.equal(obj.againstVotes);
    expect(voteCounts.abstainVotes).to.equal(obj.abstainVotes);
    expect(voteCounts.memberVoteCount).to.equal(obj.total);
  }
});
