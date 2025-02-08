// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";

interface IStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory _base, string memory _quote) external view returns (ReferenceData memory);
}

contract DUSC1 is ERC20 {
    ISemaphore public semaphore;
    IStdReference public priceOracle;
    uint256 public groupId;
    uint256 public constant MIN_COLLATERAL_RATIO = 0.75e18; // 0.75%
    uint256 public constant MAX_VALUE = 1e18; // Maximum value of collateral
    mapping(bytes32 => bool) public proofUsed;

    constructor(address _semaphore, address _priceOracle) ERC20("Decentralized Untraceable Stablecoin", "DUSC") {
        semaphore = ISemaphore(_semaphore);
        priceOracle = IStdReference(_priceOracle);
        groupId = semaphore.createGroup(address(this));
    }

    function depositCollateral(uint256 identityCommitment) external payable {
        require(msg.value == MAX_VALUE, "Collateral amount should be 1");
        semaphore.addMember(groupId, identityCommitment);
    }

    function mint(uint256 merkleTreeDepth, uint256 merkleTreeRoot, uint256 nullifier, uint256[8] calldata points)
        external
    {
        uint256 collateralValue = MAX_VALUE * getCollateralPrice() / 1e18;
        uint256 amount = (collateralValue * MIN_COLLATERAL_RATIO) / 1e18;

        ISemaphore.SemaphoreProof memory proof =
            ISemaphore.SemaphoreProof(merkleTreeDepth, merkleTreeRoot, nullifier, 0, groupId, points);

        bytes32 proofHash = keccak256(
            abi.encodePacked(
                proof.merkleTreeDepth, proof.merkleTreeRoot, proof.nullifier, proof.message, proof.scope, proof.points
            )
        );

        require(!proofUsed[proofHash], "Proof already used");

        semaphore.validateProof(groupId, proof);

        _mint(msg.sender, amount);

        proofUsed[proofHash] = true;
    }

    function getCollateralPrice() public view returns (uint256) {
        IStdReference.ReferenceData memory data = priceOracle.getReferenceData("XRP", "USD");
        return data.rate;
    }
}
