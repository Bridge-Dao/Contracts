// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./BridgeDaoTokenLock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @dev An ERC20 token for BridgeDao.
 *      Besides the addition of voting capabilities, we make a couple of customisations:
 *       - Airdrop claim functionality via `claimTokens`. At creation time the tokens that
 *         should be available for the airdrop are transferred to the token contract address;
 *         airdrop claims are made from this balance.
 */
contract BridgeDaoToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    bytes32 public merkleRoot;

    mapping(address=>bool) private claimed;

    event MerkleRootChanged(bytes32 merkleRoot);
    event Claim(address indexed claimant, uint256 amount);

    // total supply 1 trillion, 55% airdrop, 5% devs vested, 10% lp incentives, remainder to timelock
    uint256 constant airdropSupply = 550000000000000085770152383000;
    uint256 constant devSupply = 50_000_000_000e18;
    uint256 constant lpIncentive = 100_000_000_000e18;
    uint256 constant timelockSupply = 1_000_000_000_000e18 - airdropSupply - devSupply - lpIncentive;


    bool public vestStarted = false;

    uint256 public constant claimPeriodEnds = 1644019200; // Feb 5, 2022
    
    //Deployed on Avalance so this is 0.1 AVAX ~ $9
    uint256 constant private SERVICE_FEE = 100000000000000000;

    /**
     * @dev Constructor.
     * @param timelockAddress The address of the timelock.
     */
    constructor(
        address timelockAddress
    )
        ERC20("Bridge DAO", "BRDG")
        ERC20Permit("Bridge DAO")
    {
        _mint(address(this), airdropSupply);
        _mint(address(this), devSupply);
        _mint(0x6Ddc025c07Bf54565De3b655c847d221cFAaD6Ae, lpIncentive);
        _mint(timelockAddress, timelockSupply);
    }

    function startVest(address tokenLockAddress) public onlyOwner {
        require(!vestStarted, "BridgeDao: Vest has already started.");
        vestStarted = true;
        _approve(address(this), tokenLockAddress, devSupply);
        BridgeDaoTokenLock(tokenLockAddress).lock(0xf7C9F31968d97240EbAa1BE0C7b405d793584F91, 50_000_000_000e18);
    }

    /**
     * @dev Claims airdropped tokens.
     * @param amount The amount of the claim being made.
     * @param merkleProof A merkle proof proving the claim is valid.
     */
    function claimTokens(uint256 amount, bytes32[] calldata merkleProof) public payable{
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        bool valid = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        require(valid, "BridgeDao: Valid proof required.");
        require(!claimed[msg.sender], "BridgeDao: Tokens already claimed.");
        require(msg.value == SERVICE_FEE, "BridgeDao: INSUFFICIENT FUNDS");
        claimed[msg.sender] = true;
        
        emit Claim(msg.sender, amount);

        teamAddress().transfer(SERVICE_FEE);
        _transfer(address(this), msg.sender, amount);
        
    }

    /**
     * @dev Allows the owner to sweep unclaimed tokens after the claim period ends.
     * @param dest The address to sweep the tokens to.
     */
    function sweep(address dest) public onlyOwner {
        require(block.timestamp > claimPeriodEnds, "BridgeDao: Claim period not yet ended");
        _transfer(address(this), dest, balanceOf(address(this)));
    }

    /**
     * @dev Returns true if the claim at the given index in the merkle tree has already been made.
     * @param account The address to check if claimed.
     */
    function hasClaimed(address account) public view returns (bool) {
        return claimed[account];
    }

    /**
     * @dev Sets the merkle root. Only callable if the root is not yet set.
     * @param _merkleRoot The merkle root to set.
     */
    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        require(merkleRoot == bytes32(0), "BridgeDao: Merkle root already set");
        merkleRoot = _merkleRoot;
        emit MerkleRootChanged(_merkleRoot);
    }
    
    function teamAddress() public view returns (address payable) {
		return payable(address(0xABdAE08670a4015fbB9dE9Eb141f54dD31a6D8A8));
	}

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}
