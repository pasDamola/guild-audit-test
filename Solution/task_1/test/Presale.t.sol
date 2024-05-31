// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "v2-periphery/interfaces/IUniswapV2Router02.sol";
import "forge-std/console.sol";

import {PresalePlatform} from "../src/Presale.sol";
import {ERC20Mock} from "../src/ERC20Mock.sol";

contract PresalePlatformTest is Test {
    PresalePlatform public presalePlatform;
    ERC20Mock public token;
    address public uniswapRouterAddress = address(0xDEAD); // Mock address for Uniswap router
    address public owner;
    address public addr1;
    address public addr2;

    function setUp() public {
        owner = address(this);
        addr1 = address(0xAAAA);
        addr2 = address(0xBBBB);

        token = new ERC20Mock("Test Token", "TTK", 10_000);
        presalePlatform = new PresalePlatform(IERC20(address(token)), IUniswapV2Router02(uniswapRouterAddress));

        token.mint(owner, 1_000);
        token.mint(addr1, 1_000);
        token.mint(addr2, 1_000);
    }

    function createPresale() public {
        token.approve(address(presalePlatform), 1000);
        presalePlatform.createPresale(
            address(token),
            1000,
            100,
            5 days,
            2 days,
            10 days
        );
    }

      function test_createPresale() public {
        createPresale();

        (address team, address presaleToken,uint256 tokenAmount,,,,,,,,,) = presalePlatform.presales(1);
        assertEq(presaleToken, address(token));
        assertEq(tokenAmount, 1000);
        assertEq(team, owner);
    }

    function test_contribute() public {
         createPresale();

        vm.deal(addr1, 1 ether);
        vm.prank(addr1);
        presalePlatform.contribute{value: 1 ether}(1);
        assertEq(presalePlatform.contributions(1, addr1), 1 ether);
    }

     function test_finalizePresale_addLiquidity() public {
       createPresale();

        vm.deal(addr1, 100 ether);
        vm.prank(addr1);
        presalePlatform.contribute{value: 100 ether}(1);

        // Fast forward time to after presale end
        vm.warp(block.timestamp + 5 days + 2);
        
        // Finalize presale
        presalePlatform.finalizePresale(1);


        (,,,,,,,,,bool finalized, bool liquidityAdded, uint256 totalRaised) = presalePlatform.presales(1);
        assertTrue(finalized);
        assertTrue(liquidityAdded); //😭 this fails with an EVM revert error, tried to find out why before the submission deadline 
        assertEq(totalRaised, 100 ether);
    }

}
