// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IFinalistArt} from "./interfaces/IFinalistArt.sol";

/// @title Visual Identity Genesis (VIMDG)
/// @notice Edition 1 of the VisualIdentity.md community vote. identity.md seat holders pick the
///         winning brand guide by minting a vote NFT, one vote per seat id ever. Anyone may also
///         burn 50,000 VIMD to mint a collector NFT of a finalist, which is never a vote.
///
///         Immutable by design: no owner, admin, pause, upgrade, setters or withdraw. The seat
///         collection, the VIMD token and the three art contracts are fixed at deployment and the
///         constructor calls none of them.
contract BrandGenesisNFT is ERC721 {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    // ───────────────────────────── constants ─────────────────────────────

    /// @notice Edition number of this contest.
    uint256 public constant EDITION = 1;
    /// @notice Number of finalists; valid finalist indexes are 0, 1 and 2.
    uint8 public constant FINALIST_COUNT = 3;
    /// @notice Seat ids 0 to MAX_SEAT_ID inclusive may vote.
    uint256 public constant MAX_SEAT_ID = 1999;
    /// @notice Cap on vote mints (one per seat id).
    uint256 public constant MAX_VOTE_MINTS = 2000;
    /// @notice Cap on burn mints.
    uint256 public constant MAX_BURN_MINTS = 2000;
    /// @notice Exact VIMD amount a burn mint sends to the dead address.
    uint256 public constant BURN_AMOUNT = 50_000 ether;
    /// @notice Where burned VIMD goes. Nothing can move it from there.
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    /// @notice Length of the voting window after deployment.
    uint256 public constant VOTE_DURATION = 7 days;

    // ───────────────────────────── immutables ─────────────────────────────

    /// @notice The launch token burned by `mint`.
    IERC20 public immutable VIMD;
    /// @notice The identity.md seat collection whose holders vote.
    IERC721 public immutable SEATS;
    /// @notice Finalist art contracts, index 0, 1 and 2.
    IFinalistArt public immutable ART_A;
    IFinalistArt public immutable ART_B;
    IFinalistArt public immutable ART_C;
    /// @notice Votes are accepted while `block.timestamp < VOTE_END`.
    uint256 public immutable VOTE_END;

    // ───────────────────────────── state ─────────────────────────────

    /// @notice Total tokens ever minted; the next token id is `totalMinted + 1`.
    uint256 public totalMinted;
    /// @notice Total tokens burned through `burn`.
    uint256 public totalBurned;
    /// @notice Number of vote mints so far.
    uint256 public totalVoteMints;
    /// @notice Number of burn mints so far.
    uint256 public totalBurnMints;
    /// @notice Votes per finalist index.
    mapping(uint8 finalist => uint256 count) public votes;
    /// @notice Whether a seat id has already voted. Permanent, survives seat transfers and NFT burns.
    mapping(uint256 seatId => bool voted) public seatVoted;
    /// @notice Finalist index of each token id (kept after burn).
    mapping(uint256 tokenId => uint8 finalist) public finalistOf;
    /// @notice True for vote mints, false for burn mints (kept after burn).
    mapping(uint256 tokenId => bool vote) public isVoteToken;
    /// @notice Seat id a vote token was minted with (meaningless for burn mints).
    mapping(uint256 tokenId => uint256 seatId) public seatOf;

    // ───────────────────────────── events ─────────────────────────────

    event Voted(uint256 indexed seatId, uint8 indexed finalist, address indexed voter, uint256 tokenId);
    event BurnMinted(address indexed minter, uint8 indexed finalist, uint256 tokenId, uint256 vimdBurned);
    event Burned(uint256 indexed tokenId, address indexed by);

    // ───────────────────────────── errors ─────────────────────────────

    error InvalidFinalist(uint8 finalist);
    error InvalidSeat(uint256 seatId);
    error NotSeatOwner(uint256 seatId, address caller);
    error SeatAlreadyVoted(uint256 seatId);
    error VotingClosed();
    error VotingOpen();
    error NoVotes();
    error VoteMintCapReached();
    error BurnMintCapReached();
    error ZeroAddress();

    /// @param vimd The launch token (VIMD), filled by the manifest with $token.
    /// @param seats The identity.md seat collection.
    /// @param artA Finalist A art contract ($contract:FinalistArtA).
    /// @param artB Finalist B art contract ($contract:FinalistArtB).
    /// @param artC Finalist C art contract ($contract:FinalistArtC).
    constructor(address vimd, address seats, address artA, address artB, address artC)
        ERC721("Visual Identity Genesis", "VIMDG")
    {
        if (vimd == address(0) || seats == address(0) || artA == address(0) || artB == address(0) || artC == address(0))
        {
            revert ZeroAddress();
        }
        VIMD = IERC20(vimd);
        SEATS = IERC721(seats);
        ART_A = IFinalistArt(artA);
        ART_B = IFinalistArt(artB);
        ART_C = IFinalistArt(artC);
        VOTE_END = block.timestamp + VOTE_DURATION;
    }

    // ───────────────────────────── voting ─────────────────────────────

    /// @notice Vote for a finalist with a seat you hold. Mints the next token id to you.
    /// @dev One vote per seat id ever: a seat that voted and was then transferred cannot vote again.
    function vote(uint256 seatId, uint8 finalist) external {
        if (finalist >= FINALIST_COUNT) revert InvalidFinalist(finalist);
        if (block.timestamp >= VOTE_END) revert VotingClosed();
        if (seatId > MAX_SEAT_ID) revert InvalidSeat(seatId);
        if (seatVoted[seatId]) revert SeatAlreadyVoted(seatId);
        if (totalVoteMints >= MAX_VOTE_MINTS) revert VoteMintCapReached();
        if (SEATS.ownerOf(seatId) != msg.sender) revert NotSeatOwner(seatId, msg.sender);

        seatVoted[seatId] = true;
        totalVoteMints += 1;
        votes[finalist] += 1;

        uint256 tokenId = ++totalMinted;
        finalistOf[tokenId] = finalist;
        isVoteToken[tokenId] = true;
        seatOf[tokenId] = seatId;
        _mint(msg.sender, tokenId);

        emit Voted(seatId, finalist, msg.sender, tokenId);
    }

    /// @notice Burn exactly 50,000 VIMD to mint a collector token of a finalist. Never a vote.
    /// @dev Requires a prior VIMD approval of at least BURN_AMOUNT to this contract.
    function mint(uint8 finalist) external {
        if (finalist >= FINALIST_COUNT) revert InvalidFinalist(finalist);
        if (totalBurnMints >= MAX_BURN_MINTS) revert BurnMintCapReached();

        totalBurnMints += 1;
        uint256 tokenId = ++totalMinted;
        finalistOf[tokenId] = finalist;

        VIMD.safeTransferFrom(msg.sender, DEAD, BURN_AMOUNT);
        _mint(msg.sender, tokenId);

        emit BurnMinted(msg.sender, finalist, tokenId, BURN_AMOUNT);
    }

    /// @notice Burn a token you own or are approved for. Returns no VIMD and changes no vote.
    function burn(uint256 tokenId) external {
        // Reverts unless msg.sender is the owner, an approved operator, or approved for this token.
        _update(address(0), tokenId, msg.sender);
        totalBurned += 1;
        emit Burned(tokenId, msg.sender);
    }

    // ───────────────────────────── results ─────────────────────────────

    /// @notice The most-voted finalist so far; the lowest index wins a tie. Reverts with no votes.
    function leader() public view returns (uint8) {
        uint8 best = 0;
        uint256 bestVotes = votes[0];
        for (uint8 i = 1; i < FINALIST_COUNT; ++i) {
            uint256 v = votes[i];
            if (v > bestVotes) {
                best = i;
                bestVotes = v;
            }
        }
        if (bestVotes == 0) revert NoVotes();
        return best;
    }

    /// @notice The final result. Reverts while voting is open and when no votes were cast.
    function winner() external view returns (uint8) {
        if (block.timestamp < VOTE_END) revert VotingOpen();
        return leader();
    }

    /// @notice Total votes across all finalists.
    function totalVotes() external view returns (uint256) {
        return votes[0] + votes[1] + votes[2];
    }

    /// @notice True while votes are accepted.
    function votingOpen() external view returns (bool) {
        return block.timestamp < VOTE_END;
    }

    /// @notice Current number of live tokens.
    function totalSupply() external view returns (uint256) {
        return totalMinted - totalBurned;
    }

    // ───────────────────────────── metadata ─────────────────────────────

    /// @notice The art contract of a finalist index.
    function artOf(uint8 finalist) public view returns (IFinalistArt) {
        if (finalist == 0) return ART_A;
        if (finalist == 1) return ART_B;
        if (finalist == 2) return ART_C;
        revert InvalidFinalist(finalist);
    }

    /// @notice Base64 data URI of a JSON document whose image is the finalist's logomark SVG, Base64 encoded.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint8 finalist = finalistOf[tokenId];
        string memory letter = _letter(finalist);
        string memory svg = artOf(finalist).logomark();
        bool isVote = isVoteToken[tokenId];

        string memory attributes = string.concat(
            '[{"trait_type":"Edition","value":"',
            EDITION.toString(),
            '"},{"trait_type":"Finalist","value":"',
            letter,
            '"},{"trait_type":"Type","value":"',
            isVote ? "Vote" : "Burn",
            '"},',
            isVote ? string.concat('{"trait_type":"Seat","value":"', seatOf[tokenId].toString(), '"},') : "",
            '{"trait_type":"Number","value":"',
            tokenId.toString(),
            '"}]'
        );

        string memory json = string.concat(
            '{"name":"Visual Identity Genesis #',
            tokenId.toString(),
            '","description":"VisualIdentity.md Edition 1: a community proposal for IMD\'s visual identity. Finalist ',
            letter,
            isVote ? ". Minted by a seat holder vote." : ". Minted by burning 50,000 VIMD; not a vote.",
            '","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":',
            attributes,
            "}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _letter(uint8 finalist) private pure returns (string memory) {
        if (finalist == 0) return "A";
        if (finalist == 1) return "B";
        return "C";
    }
}
