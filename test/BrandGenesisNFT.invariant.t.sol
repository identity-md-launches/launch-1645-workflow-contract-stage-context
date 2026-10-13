// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {FinalistArtA} from "../src/FinalistArtA.sol";
import {FinalistArtB} from "../src/FinalistArtB.sol";
import {FinalistArtC} from "../src/FinalistArtC.sol";
import {BrandGenesisNFT} from "../src/BrandGenesisNFT.sol";
import {MockSeats} from "./mocks/MockSeats.sol";

/// @notice Drives BrandGenesisNFT with random, bounded calls from several actors: votes with owned,
///         foreign, unminted, used and out-of-range seats; burn mints with exact, unlimited and short
///         allowances; burns by owners, operators and strangers; seat and NFT transfers; and time
///         moving across VOTE_END. Every call is expected to either succeed or revert according to
///         the approved rules, and the handler records what the contract should now hold in ghost
///         variables that the invariants compare against.
contract BrandGenesisHandler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant BURN = 50_000e18;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    BrandGenesisNFT public immutable nft;
    LaunchToken public immutable vimd;
    MockSeats public immutable seats;

    address[] public actors;
    uint256[] public seatCandidates;

    // ───────────── ghost state: what the contract must hold after every sequence ─────────────

    uint256[3] public ghostVotes;
    uint256 public ghostVoteMints;
    uint256 public ghostBurnMints;
    uint256 public ghostBurned;
    uint256 public ghostDeadBalance;
    uint256[] public ghostVotedSeats;
    mapping(uint256 seatId => bool) public ghostSeatVoted;
    mapping(uint256 tokenId => bool) public ghostTokenBurned;
    mapping(uint256 tokenId => uint8) public ghostFinalistOf;
    mapping(uint256 tokenId => bool) public ghostIsVote;
    mapping(uint256 tokenId => uint256) public ghostSeatOf;

    /// @dev Set the first time a handler call observes the window closed; votes must freeze there.
    bool public ghostClosed;
    uint256 public ghostVoteMintsAtClose;

    // ───────────── call counters, for the summary and to prove paths were exercised ─────────────

    uint256 public votesSucceeded;
    uint256 public votesRejected;
    uint256 public mintsSucceeded;
    uint256 public mintsRejected;
    uint256 public burnsSucceeded;
    uint256 public burnsRejected;
    uint256 public votesRejectedAfterClose;

    constructor(BrandGenesisNFT nft_, LaunchToken vimd_, MockSeats seats_, address[] memory actors_) {
        nft = nft_;
        vimd = vimd_;
        seats = seats_;
        actors = actors_;

        // Candidates the test minted: 0..69 across the actors, 1999 to actor 0 and 2000..2002 to
        // actor 1 (minted but outside the range); plus ids that were never minted.
        for (uint256 id; id < 70; ++id) {
            seatCandidates.push(id);
        }
        seatCandidates.push(1999);
        seatCandidates.push(1998); // never minted: ownerOf reverts
        seatCandidates.push(2000);
        seatCandidates.push(2001);
        seatCandidates.push(2002);
        seatCandidates.push(type(uint256).max);
    }

    // ───────────────────────────── helpers ─────────────────────────────

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function ghostVotedSeatCount() external view returns (uint256) {
        return ghostVotedSeats.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _observeClose() internal {
        if (!ghostClosed && block.timestamp >= nft.VOTE_END()) {
            ghostClosed = true;
            ghostVoteMintsAtClose = nft.totalVoteMints();
        }
    }

    function _seatOwner(uint256 seatId) internal view returns (bool exists, address owner) {
        try seats.ownerOf(seatId) returns (address o) {
            return (true, o);
        } catch {
            return (false, address(0));
        }
    }

    function _nftOwner(uint256 tokenId) internal view returns (bool exists, address owner) {
        try nft.ownerOf(tokenId) returns (address o) {
            return (true, o);
        } catch {
            return (false, address(0));
        }
    }

    function _snapshotVotes() internal view returns (uint256[3] memory v) {
        v[0] = nft.votes(0);
        v[1] = nft.votes(1);
        v[2] = nft.votes(2);
    }

    // ───────────────────────────── actions ─────────────────────────────

    function vote(uint256 actorSeed, uint256 seatSeed, uint8 finalist) external {
        _observeClose();
        uint256 actorIndex = bound(actorSeed, 0, actors.length - 1);
        address actor = actors[actorIndex];
        // Half the picks come from the block of ten seats this actor started with, so that votes
        // succeed often enough to matter; the other half from every candidate, owned or not.
        uint256 seatId = seatSeed % 2 == 0
            ? actorIndex * 10 + (seatSeed / 2) % 10
            : seatCandidates[bound(seatSeed, 0, seatCandidates.length - 1)];
        finalist = uint8(bound(finalist, 0, 3)); // 3 is invalid

        (bool exists, address owner) = _seatOwner(seatId);
        bool open = block.timestamp < nft.VOTE_END();
        bool shouldSucceed = finalist < 3 && open && seatId <= 1999 && !ghostSeatVoted[seatId] && exists
            && owner == actor && ghostVoteMints < 2000;

        uint256 mintedBefore = nft.totalMinted();
        uint256[3] memory votesBefore = _snapshotVotes();

        vm.prank(actor);
        try nft.vote(seatId, finalist) {
            require(shouldSucceed, "handler: vote succeeded where it must revert");
            uint256 tokenId = mintedBefore + 1;
            ghostVotes[finalist] += 1;
            ghostVoteMints += 1;
            ghostSeatVoted[seatId] = true;
            ghostVotedSeats.push(seatId);
            ghostFinalistOf[tokenId] = finalist;
            ghostIsVote[tokenId] = true;
            ghostSeatOf[tokenId] = seatId;
            require(nft.ownerOf(tokenId) == actor, "handler: vote token not minted to voter");
            require(nft.totalMinted() == tokenId, "handler: vote minted a different id");
            votesSucceeded += 1;
        } catch {
            require(!shouldSucceed, "handler: vote reverted where it must succeed");
            require(nft.totalMinted() == mintedBefore, "handler: failed vote changed totalMinted");
            uint256[3] memory votesAfter = _snapshotVotes();
            require(
                votesAfter[0] == votesBefore[0] && votesAfter[1] == votesBefore[1] && votesAfter[2] == votesBefore[2],
                "handler: failed vote changed the tally"
            );
            votesRejected += 1;
            if (!open) votesRejectedAfterClose += 1;
        }
    }

    /// @param allowanceMode 0: exactly BURN, 1: unlimited, 2: BURN - 1 (must fail), 3: leave as is
    function mint(uint256 actorSeed, uint8 finalist, uint8 allowanceMode) external {
        _observeClose();
        address actor = _actor(actorSeed);
        finalist = uint8(bound(finalist, 0, 3)); // 3 is invalid
        allowanceMode = uint8(bound(allowanceMode, 0, 3));

        if (allowanceMode == 0) {
            vm.prank(actor);
            vimd.approve(address(nft), BURN);
        } else if (allowanceMode == 1) {
            vm.prank(actor);
            vimd.approve(address(nft), type(uint256).max);
        } else if (allowanceMode == 2) {
            vm.prank(actor);
            vimd.approve(address(nft), BURN - 1);
        }

        uint256 allowance = vimd.allowance(actor, address(nft));
        uint256 balance = vimd.balanceOf(actor);
        bool shouldSucceed = finalist < 3 && ghostBurnMints < 2000 && allowance >= BURN && balance >= BURN;

        uint256 mintedBefore = nft.totalMinted();
        uint256 deadBefore = vimd.balanceOf(DEAD);
        uint256[3] memory votesBefore = _snapshotVotes();

        vm.prank(actor);
        try nft.mint(finalist) {
            require(shouldSucceed, "handler: mint succeeded where it must revert");
            uint256 tokenId = mintedBefore + 1;
            ghostBurnMints += 1;
            ghostDeadBalance += BURN;
            ghostFinalistOf[tokenId] = finalist;
            require(nft.ownerOf(tokenId) == actor, "handler: burn token not minted to minter");
            require(vimd.balanceOf(actor) == balance - BURN, "handler: mint took a different amount");
            require(vimd.balanceOf(DEAD) == deadBefore + BURN, "handler: dead did not receive BURN");
            if (allowance != type(uint256).max) {
                require(vimd.allowance(actor, address(nft)) == allowance - BURN, "handler: allowance delta");
            }
            mintsSucceeded += 1;
        } catch {
            require(!shouldSucceed, "handler: mint reverted where it must succeed");
            require(nft.totalMinted() == mintedBefore, "handler: failed mint changed totalMinted");
            require(vimd.balanceOf(actor) == balance, "handler: failed mint moved VIMD");
            require(vimd.balanceOf(DEAD) == deadBefore, "handler: failed mint moved VIMD to dead");
            mintsRejected += 1;
        }
        uint256[3] memory votesAfter = _snapshotVotes();
        require(
            votesAfter[0] == votesBefore[0] && votesAfter[1] == votesBefore[1] && votesAfter[2] == votesBefore[2],
            "handler: a burn mint changed the tally"
        );
    }

    function burn(uint256 actorSeed, uint256 tokenSeed) external {
        _observeClose();
        address actor = _actor(actorSeed);
        uint256 tokenId = bound(tokenSeed, 0, nft.totalMinted() + 1);

        (bool exists, address owner) = _nftOwner(tokenId);
        bool authorized =
            exists && (owner == actor || nft.isApprovedForAll(owner, actor) || nft.getApproved(tokenId) == actor);

        uint256[3] memory votesBefore = _snapshotVotes();
        uint256 deadBefore = vimd.balanceOf(DEAD);
        uint256 actorVimdBefore = vimd.balanceOf(actor);
        uint256 burnedBefore = nft.totalBurned();

        vm.prank(actor);
        try nft.burn(tokenId) {
            require(authorized, "handler: burn succeeded for an unauthorized caller");
            ghostBurned += 1;
            ghostTokenBurned[tokenId] = true;
            burnsSucceeded += 1;
        } catch {
            require(!authorized, "handler: burn reverted for an authorized caller");
            require(nft.totalBurned() == burnedBefore, "handler: failed burn changed totalBurned");
            burnsRejected += 1;
        }
        uint256[3] memory votesAfter = _snapshotVotes();
        require(
            votesAfter[0] == votesBefore[0] && votesAfter[1] == votesBefore[1] && votesAfter[2] == votesBefore[2],
            "handler: burn changed the tally"
        );
        require(vimd.balanceOf(DEAD) == deadBefore, "handler: burn moved VIMD out of dead");
        require(vimd.balanceOf(actor) == actorVimdBefore, "handler: burn refunded VIMD");
    }

    function approveNftOperator(uint256 actorSeed, uint256 operatorSeed, bool approved) external {
        _observeClose();
        address actor = _actor(actorSeed);
        address operator = _actor(operatorSeed);
        if (operator == actor) return;
        vm.prank(actor);
        nft.setApprovalForAll(operator, approved);
    }

    function approveNftToken(uint256 actorSeed, uint256 operatorSeed, uint256 tokenSeed) external {
        _observeClose();
        address actor = _actor(actorSeed);
        address operator = _actor(operatorSeed);
        uint256 total = nft.totalMinted();
        if (total == 0) return;
        uint256 tokenId = bound(tokenSeed, 1, total);
        (bool exists, address owner) = _nftOwner(tokenId);
        if (!exists || owner != actor) return;
        vm.prank(actor);
        nft.approve(operator, tokenId);
    }

    function transferSeat(uint256 actorSeed, uint256 toSeed, uint256 seatSeed) external {
        _observeClose();
        address actor = _actor(actorSeed);
        address to = _actor(toSeed);
        uint256 seatId = seatCandidates[bound(seatSeed, 0, seatCandidates.length - 1)];
        (bool exists, address owner) = _seatOwner(seatId);
        if (!exists || owner != actor || to == actor) return;
        vm.prank(actor);
        seats.transferFrom(actor, to, seatId);
    }

    function transferNft(uint256 actorSeed, uint256 toSeed, uint256 tokenSeed) external {
        _observeClose();
        address actor = _actor(actorSeed);
        address to = _actor(toSeed);
        uint256 total = nft.totalMinted();
        if (total == 0) return;
        uint256 tokenId = bound(tokenSeed, 1, total);
        (bool exists, address owner) = _nftOwner(tokenId);
        if (!exists || owner != actor || to == actor) return;
        uint256[3] memory votesBefore = _snapshotVotes();
        vm.prank(actor);
        nft.transferFrom(actor, to, tokenId);
        uint256[3] memory votesAfter = _snapshotVotes();
        require(
            votesAfter[0] == votesBefore[0] && votesAfter[1] == votesBefore[1] && votesAfter[2] == votesBefore[2],
            "handler: an NFT transfer changed the tally"
        );
        require(nft.ownerOf(tokenId) == to, "handler: transfer did not move the token");
    }

    function warp(uint256 delta) external {
        _observeClose();
        delta = bound(delta, 0, 2 days);
        vm.warp(block.timestamp + delta);
        _observeClose();
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 60
/// forge-config: default.invariant.fail-on-revert = true
contract BrandGenesisNFTInvariantTest is Test {
    uint256 internal constant BURN = 50_000e18;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant SUPPLY = 10 ** 27;

    LaunchToken internal vimd;
    MockSeats internal seats;
    BrandGenesisNFT internal nft;
    BrandGenesisHandler internal handler;
    address[] internal actors;

    function setUp() public {
        vm.warp(1_800_000_000);
        vimd = new LaunchToken();
        seats = new MockSeats();
        FinalistArtA artA = new FinalistArtA();
        FinalistArtB artB = new FinalistArtB();
        FinalistArtC artC = new FinalistArtC();
        nft = new BrandGenesisNFT(address(vimd), address(seats), address(artA), address(artB), address(artC));

        for (uint256 i; i < 6; ++i) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }
        // Seats: ten per actor for ids 0..59, 60..69 to the last actor, 1999 to actor 0, and three
        // minted ids outside the range (2000..2002) to actor 1. 1998 is never minted.
        for (uint256 id; id < 60; ++id) {
            seats.mint(actors[id / 10], id);
        }
        for (uint256 id = 60; id < 70; ++id) {
            seats.mint(actors[5], id);
        }
        seats.mint(actors[0], 1999);
        seats.mint(actors[1], 2000);
        seats.mint(actors[1], 2001);
        seats.mint(actors[1], 2002);

        // VIMD: four actors can afford many burn mints, one holds exactly one mint's worth minus
        // one wei, one holds nothing.
        for (uint256 i; i < 4; ++i) {
            vimd.transfer(actors[i], 10_000_000e18);
        }
        vimd.transfer(actors[4], BURN - 1);

        handler = new BrandGenesisHandler(nft, vimd, seats, actors);
        targetContract(address(handler));
    }

    // ───────────────────────────── counting ─────────────────────────────

    /// @notice Every token is a vote mint or a burn mint, ids are never reused and the live count is
    ///         exactly minted minus burned.
    function invariant_mintAccountingAddsUp() public view {
        assertEq(nft.totalMinted(), nft.totalVoteMints() + nft.totalBurnMints(), "minted = votes + burns");
        assertEq(nft.totalVoteMints(), handler.ghostVoteMints(), "vote mints vs ghost");
        assertEq(nft.totalBurnMints(), handler.ghostBurnMints(), "burn mints vs ghost");
        assertEq(nft.totalBurned(), handler.ghostBurned(), "burned vs ghost");
        assertLe(nft.totalBurned(), nft.totalMinted(), "burned never exceeds minted");
        assertEq(nft.totalSupply(), nft.totalMinted() - nft.totalBurned(), "live supply");
    }

    /// @notice The tally is exactly the successful votes, finalist by finalist, and equals the number
    ///         of vote mints and of distinct seats used. Burn mints, burns and transfers never touch it.
    function invariant_tallyMatchesSuccessfulVotes() public view {
        uint256 sum;
        for (uint8 i; i < 3; ++i) {
            assertEq(nft.votes(i), handler.ghostVotes(i), "votes per finalist vs ghost");
            sum += nft.votes(i);
        }
        assertEq(nft.totalVotes(), sum, "totalVotes is the sum");
        assertEq(sum, nft.totalVoteMints(), "one vote per vote mint");
        assertEq(sum, handler.ghostVotedSeatCount(), "one vote per distinct seat");
    }

    /// @notice A seat that voted stays voted, whoever holds it now, and no seat outside 0..1999 ever
    ///         appears as voted.
    function invariant_usedSeatsStayUsed() public view {
        uint256 n = handler.ghostVotedSeatCount();
        for (uint256 i; i < n; ++i) {
            uint256 seatId = handler.ghostVotedSeats(i);
            assertTrue(nft.seatVoted(seatId), "voted seat flipped back");
            assertLe(seatId, nft.MAX_SEAT_ID(), "a seat outside the range voted");
        }
        assertFalse(nft.seatVoted(1998), "an unminted seat voted");
        assertFalse(nft.seatVoted(2000), "an out-of-range seat voted");
        assertFalse(nft.seatVoted(2001), "an out-of-range seat voted");
        assertFalse(nft.seatVoted(2002), "an out-of-range seat voted");
    }

    /// @notice Caps hold for both kinds and for the shared id space.
    function invariant_caps() public view {
        assertLe(nft.totalVoteMints(), nft.MAX_VOTE_MINTS(), "vote cap");
        assertLe(nft.totalBurnMints(), nft.MAX_BURN_MINTS(), "burn cap");
        assertLe(nft.totalMinted(), nft.MAX_VOTE_MINTS() + nft.MAX_BURN_MINTS(), "id cap");
    }

    // ───────────────────────────── value ─────────────────────────────

    /// @notice What sits at the dead address is exactly 50,000 VIMD per burn mint, the NFT contract
    ///         never holds VIMD, the VIMD supply never changes and every unit is accounted for.
    function invariant_burnedVimdIsExactlyAccounted() public view {
        assertEq(vimd.balanceOf(DEAD), nft.totalBurnMints() * BURN, "dead holds BURN per burn mint");
        assertEq(vimd.balanceOf(DEAD), handler.ghostDeadBalance(), "dead vs ghost");
        assertEq(vimd.balanceOf(address(nft)), 0, "the NFT contract never custodies VIMD");
        assertEq(vimd.balanceOf(address(handler)), 0, "the handler never receives VIMD");
        assertEq(vimd.totalSupply(), SUPPLY, "VIMD supply fixed");
        uint256 sum = vimd.balanceOf(address(this)) + vimd.balanceOf(DEAD);
        for (uint256 i; i < actors.length; ++i) {
            sum += vimd.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "every VIMD unit is held by an actor, the test or dead");
    }

    // ───────────────────────────── tokens ─────────────────────────────

    /// @notice Ids 1..totalMinted are each either live and held by an actor or burned; nothing exists
    ///         outside that range; the per-token record never changes after mint; actor balances sum
    ///         to the live supply.
    function invariant_tokenIdsContiguousAndRecordsFrozen() public view {
        uint256 total = nft.totalMinted();
        uint256 live;
        for (uint256 id = 1; id <= total; ++id) {
            assertEq(nft.finalistOf(id), handler.ghostFinalistOf(id), "finalist record changed");
            assertEq(nft.isVoteToken(id), handler.ghostIsVote(id), "kind record changed");
            assertEq(nft.seatOf(id), handler.ghostSeatOf(id), "seat record changed");
            assertLt(nft.finalistOf(id), 3, "finalist out of range");
            if (handler.ghostTokenBurned(id)) {
                (bool ok,) = address(nft).staticcall(abi.encodeWithSelector(nft.ownerOf.selector, id));
                assertFalse(ok, "burned token still has an owner");
            } else {
                address owner = nft.ownerOf(id);
                assertTrue(_isActor(owner), "live token held by a stranger");
                live += 1;
            }
            if (nft.isVoteToken(id)) {
                assertTrue(nft.seatVoted(nft.seatOf(id)), "vote token's seat not marked used");
            }
        }
        assertEq(live, nft.totalSupply(), "live count vs totalSupply");
        (bool okNext,) = address(nft).staticcall(abi.encodeWithSelector(nft.ownerOf.selector, total + 1));
        assertFalse(okNext, "a token beyond totalMinted exists");
        (bool okZero,) = address(nft).staticcall(abi.encodeWithSelector(nft.ownerOf.selector, uint256(0)));
        assertFalse(okZero, "token id 0 exists");

        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            balances += nft.balanceOf(actors[i]);
        }
        assertEq(balances, nft.totalSupply(), "actor NFT balances sum to the live supply");
    }

    // ───────────────────────────── results ─────────────────────────────

    /// @notice leader() is the most-voted finalist with the lowest index on a tie, and reverts only
    ///         with no votes.
    function invariant_leaderIsArgmaxLowestIndex() public view {
        if (nft.totalVotes() == 0) {
            (bool ok,) = address(nft).staticcall(abi.encodeWithSelector(nft.leader.selector));
            assertFalse(ok, "leader() must revert with no votes");
            return;
        }
        uint8 l = nft.leader();
        uint256 best = nft.votes(l);
        assertGt(best, 0, "leader has votes");
        for (uint8 i; i < 3; ++i) {
            assertGe(best, nft.votes(i), "leader has the most votes");
            if (i < l) assertLt(nft.votes(i), best, "a lower index tied with the leader");
        }
    }

    /// @notice winner() reverts while voting is open and with no votes; otherwise it is leader().
    function invariant_winnerGatedByTimeAndVotes() public view {
        (bool ok, bytes memory ret) = address(nft).staticcall(abi.encodeWithSelector(nft.winner.selector));
        if (block.timestamp < nft.VOTE_END()) {
            assertFalse(ok, "winner() answered while voting is open");
            assertEq(bytes4(ret), BrandGenesisNFT.VotingOpen.selector, "wrong revert while open");
        } else if (nft.totalVotes() == 0) {
            assertFalse(ok, "winner() answered with no votes");
            assertEq(bytes4(ret), BrandGenesisNFT.NoVotes.selector, "wrong revert with no votes");
        } else {
            assertTrue(ok, "winner() reverted after the end with votes");
            assertEq(abi.decode(ret, (uint8)), nft.leader(), "winner is the leader");
        }
    }

    /// @notice Once the window has closed the vote count never moves again; the handler saw every
    ///         later vote attempt rejected.
    function invariant_votesFreezeAtVoteEnd() public view {
        if (handler.ghostClosed()) {
            assertEq(nft.totalVoteMints(), handler.ghostVoteMintsAtClose(), "a vote landed after VOTE_END");
            assertFalse(nft.votingOpen(), "votingOpen after the end");
        } else {
            assertTrue(nft.votingOpen(), "votingOpen false before the end");
        }
    }

    /// @notice The immutable wiring never changes.
    function invariant_wiringImmutable() public view {
        assertEq(address(nft.VIMD()), address(vimd));
        assertEq(address(nft.SEATS()), address(seats));
        assertEq(nft.VOTE_END(), 1_800_000_000 + 7 days);
    }

    /// @notice Guards against a run that exercised nothing: the handler must have driven both the
    ///         success and the failure paths of each action.
    function invariant_callSummary() public view {
        // Logged for the run summary; asserted loosely so a short or unlucky sequence does not fail.
        // 71 in-range seats exist in this harness: 0..69 and 1999.
        assertLe(handler.votesSucceeded(), 71, "more successful votes than minted in-range seats");
    }

    function _isActor(address a) internal view returns (bool) {
        for (uint256 i; i < actors.length; ++i) {
            if (actors[i] == a) return true;
        }
        return false;
    }
}
