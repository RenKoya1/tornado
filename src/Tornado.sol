// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MerkleTreeWithHistory.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface IVerifier {
       function verifyProof(uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c, uint256[5] memory input)
        external
        returns (bool);
}

contract Tornado is MerkleTreeWithHistory, ReentrancyGuard {
    IVerifier public immutable verifier;
    uint256 public denomination;

    mapping(bytes32 => bool) public nullifierHashes;
    // we store all commitments just to prevent accidental deposits with the same commitment
    mapping(bytes32 => bool) public commitments;

    event Deposit(bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
    event Withdrawal(address to, bytes32 nullifierHash, address indexed relayer, uint256 fee);

    /**
     * @dev The constructor
     * @param _verifier the address of SNARK verifier for this contract (circom proof verifier)
     * @param _hasher the address of MiMC hash contract
     * @param _denomination transfer amount for each deposit
     * @param _merkleTreeHeight the height of deposits' Merkle Tree
     */
    constructor(IVerifier _verifier, IHasher _hasher, uint256 _denomination, uint32 _merkleTreeHeight)
        MerkleTreeWithHistory(_merkleTreeHeight, _hasher)
    {
        require(_denomination > 0, "denomination should be greater than 0");
        verifier = _verifier;
        denomination = _denomination;
    }

    /**
     * @dev Deposit funds into the contract. The caller must send (for ETH) or approve (for ERC20) value equal to or `denomination` of this instance.
     * @param _commitment the note commitment, which is PedersenHash(nullifier + secret)
     */
    function deposit(bytes32 _commitment) external payable nonReentrant {
        require(!commitments[_commitment], "The commitment has been submitted");
        require(msg.value == denomination, "Please send `denomination` ETH along with transaction");

        uint32 insertedIndex = _insert(_commitment);
        commitments[_commitment] = true;

        emit Deposit(_commitment, insertedIndex, block.timestamp);
    }

    /**
     * @dev Withdraw a deposit from the contract. `proof` is a zkSNARK proof data, and input is an array of circuit public inputs
     * `input` array consists of:
     *   - merkle root of all deposits in the contract
     *   - hash of unique deposit nullifier to prevent double spends
     *   - the recipient of funds
     *   - optional fee that goes to the transaction sender (usually a relay)
     */
    function withdraw(
        bytes calldata _proof,
        bytes32 _root,
        bytes32 _nullifierHash,
        address payable _recipient,
        address payable _relayer,
        uint256 _fee
    ) external payable nonReentrant {
        require(_fee <= denomination, "Fee exceeds transfer value");
        require(!nullifierHashes[_nullifierHash], "The note has been already spent");
        require(isKnownRoot(_root), "Cannot find your merkle root"); // Make sure to use a recent one
        uint256[8] memory p = abi.decode(_proof, (uint256[8]));
        require(
            verifier.verifyProof(
                [p[0], p[1]],
                [[p[2], p[3]], [p[4], p[5]]],
                [p[6], p[7]],
                [
                    uint256(_root),
                    uint256(_nullifierHash),
                    uint256(uint160(address(_recipient))),
                    uint256(uint160(address(_relayer))),
                    _fee
                ]
            ),
            "Invalid withdraw proof"
        );

        nullifierHashes[_nullifierHash] = true;
        (bool success,) = _recipient.call{value: denomination - _fee}("");
        require(success, "Payment to recipient failed");
        if (_fee > 0) {
            (success,) = _relayer.call{value: _fee}("");
            require(success, "Payment to relayer failed");
        }
        emit Withdrawal(_recipient, _nullifierHash, _relayer, _fee);
    }

    /**
     * @dev whether a note is already spent
     */
    function isSpent(bytes32 _nullifierHash) public view returns (bool) {
        return nullifierHashes[_nullifierHash];
    }
}


