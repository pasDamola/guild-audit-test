// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "v2-periphery/interfaces/IUniswapV2Router02.sol";

/**
 * @title PresalePlatform
 * @dev A permissionless platform to conduct token presales and manage liquidity provision on Uniswap.
 */
contract PresalePlatform is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct Presale {
        address team;
        address token;
        uint256 tokenAmount;
        uint256 ethAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 deadline;
        uint256 vestingPeriod;
        bool initialized;
        bool finalized;
        bool liquidityAdded;
        uint256 totalRaised;
        address[] contributors;
    }

     /********************** State Info ***********************/
    uint256 public platformFee = 1; // Platform fee as a percentage (1%)
    mapping(uint256 => Presale) public presales;
    uint256 public presaleCount;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => mapping(address => uint256)) public claimedTokens;
    IERC20 public platformToken;
    IUniswapV2Router02 public uniswapRouter;


     /********************** Events ***********************/
    event PresaleCreated(uint256 indexed presaleId, address indexed team, address indexed token);
    event PresaleFinalized(uint256 indexed presaleId, uint256 totalRaised);
    event LiquidityAdded(uint256 indexed presaleId, uint256 ethAmount, uint256 tokenAmount);

  
    constructor(IERC20 _platformToken, IUniswapV2Router02 _uniswapRouter) {
        platformToken = _platformToken;
        uniswapRouter = _uniswapRouter;
    }

    /**
     * @notice Creates a new presale.
     * @param token The address of the token to be sold.
     * @param tokenAmount The total amount of tokens to be sold.
     * @param ethAmount The amount of ETH to be raised.
     * @param duration The duration of the presale in seconds.
     * @param deadline The deadline in seconds after the presale ends.
     * @param vestingPeriod The vesting period in seconds for token release.
     */
    function createPresale(
        address token,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 duration,
        uint256 deadline,
        uint256 vestingPeriod
    ) external nonReentrant {
        require(token != address(0), "Invalid token address");
        require(tokenAmount > 0, "Invalid token amount");
        require(ethAmount > 0, "Invalid ETH amount");
        require(duration > 0, "Invalid duration");
        require(deadline > 0, "Invalid deadline");
        require(vestingPeriod > 0, "Invalid vesting period");

        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);


        presaleCount++;
        address[] memory contributors;
        Presale storage newPresale = presales[presaleCount];
        newPresale.team = msg.sender;
        newPresale.token = token;
        newPresale.tokenAmount = tokenAmount;
        newPresale.ethAmount = ethAmount;
        newPresale.startTime = block.timestamp;
        newPresale.endTime = block.timestamp + duration;
        newPresale.deadline = block.timestamp + duration + deadline;
        newPresale.vestingPeriod = vestingPeriod;
        newPresale.initialized = true;
        newPresale.finalized = false;
        newPresale.liquidityAdded = false;
        newPresale.totalRaised = 0;
        newPresale.contributors = contributors;

        emit PresaleCreated(presaleCount, msg.sender, token);
    }

    /**
     * @notice Contribute ETH to a presale.
     * @param presaleId The ID of the presale to contribute to.
     */
    function contribute(uint256 presaleId) external payable nonReentrant {
        Presale storage presale = presales[presaleId];
        require(presale.initialized, "Presale not initialized");
        require(block.timestamp >= presale.startTime, "Presale not started");
        require(block.timestamp <= presale.endTime, "Presale ended");
        require(msg.value > 0, "Contribution cannot be zero");

        presale.totalRaised += msg.value;
        contributions[presaleId][msg.sender] += msg.value;
        presale.contributors.push(msg.sender);
    }

    /**
     * @notice Finalize a presale after it ends.
     * @param presaleId The ID of the presale to finalize.
     */
    function finalizePresale(uint256 presaleId) external nonReentrant {
        Presale storage presale = presales[presaleId];
        require(presale.initialized, "Presale not initialized");
        require(block.timestamp > presale.endTime, "Presale not ended");
        require(!presale.finalized, "Presale already finalized");
        require(msg.sender == presale.team, "Only team can finalize");

        uint256 fee = (presale.totalRaised * platformFee) / 100;
        uint256 netRaised = presale.totalRaised - fee;


        payable(owner()).transfer(fee);

        presale.finalized = true;

        emit PresaleFinalized(presaleId, presale.totalRaised);

        if (netRaised >= presale.ethAmount) {
            _addLiquidity(presaleId, netRaised);
        } else {
            _refundContributors(presaleId);
        }
    }

    /**
     * @dev Internal function to add liquidity to Uniswap.
     * @param presaleId The ID of the presale.
     * @param ethAmount The amount of ETH to add to the liquidity pool.
     */
    function _addLiquidity(uint256 presaleId, uint256 ethAmount) internal {
        Presale storage presale = presales[presaleId];
        IERC20(presale.token).approve(address(uniswapRouter), presale.tokenAmount);
        uniswapRouter.addLiquidityETH{value: ethAmount}(
            presale.token,
            presale.tokenAmount,
            0,
            0,
            presale.team,
            block.timestamp + 15 minutes
        );

        presale.liquidityAdded = true;

        emit LiquidityAdded(presaleId, ethAmount, presale.tokenAmount);
    }

    /**
     * @dev Internal function to refund all contributors if presale fails.
     * @param presaleId The ID of the presale.
     */
    function _refundContributors(uint256 presaleId) internal {
        Presale storage presale = presales[presaleId];
        for (uint256 i = 0; i < presale.contributors.length; i++) {
            address contributor = presale.contributors[i];
            uint256 contribution = contributions[presaleId][contributor];
            payable(contributor).transfer(contribution);
        }
    }

    /**
     * @notice Claim tokens after the vesting period.
     * @param presaleId The ID of the presale to claim tokens from.
     */
    function claimTokens(uint256 presaleId) external nonReentrant {
        Presale storage presale = presales[presaleId];
        require(presale.finalized, "Presale not finalized");
        require(presale.liquidityAdded, "Liquidity not added");

        uint256 totalContribution = contributions[presaleId][msg.sender];
        require(totalContribution > 0, "No contribution found");

        uint256 vestingDuration = block.timestamp - presale.endTime;
        uint256 vestingPeriodsPassed = vestingDuration / (presale.vestingPeriod / 10);

        uint256 totalClaimable = (totalContribution * vestingPeriodsPassed) / 10;
        uint256 claimed = claimedTokens[presaleId][msg.sender];

        require(totalClaimable > claimed, "No tokens to claim");

        uint256 claimAmount = totalClaimable - claimed;
        claimedTokens[presaleId][msg.sender] += claimAmount;

        IERC20(presale.token).transfer(msg.sender, claimAmount);
    }

    /**
     * @notice Set the platform fee.
     * @param fee The new platform fee as a percentage.
     */
    function setPlatformFee(uint256 fee) external onlyOwner {
        platformFee = fee;
    }
}