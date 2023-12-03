// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

//import {CreateSubscription} from "../../script/Interactions.s.sol"; we do not need this shit

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;
    /**Events */ // We write it here because event is not type of data and it can not be imported from Main
    // contract;
    event enteredRaffle(address indexed player);
    /////////////////////////////////////////////
    address public PLAYER = makeAddr("beef");
    uint256 public constant STARTING_BALANCE = 10 ether;
    //////////////////////////////////
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    //////////////////////////////////////////

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_BALANCE);
    }

    /**TESTS */

    function testRaffleOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.Open);
    }

    /////////////////////////////////////////////////////////////
    function testRaffleRevertsWhenNotEnoughMoney() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle_notEnoughEthSent.selector);
        raffle.enterRaffle{value: 0.005 ether}();
    }

    function testPlayerRecordedWhenEntered() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testEmitEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit enteredRaffle(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    function testCanNotEnterRaffleCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // time machine, imitates that interval has passed
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle_RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();

        //////////
        /// checkUpkeep ///
        ////////////
    }

    function testUpkeepReturnFalseWhenNoMoney() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded); // ! before bool means it has value FALSE !!!
    }

    function testcheckUpkeepReturnFalseWhenRaffleNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(!upkeepNeeded);
        assert(raffleState == Raffle.RaffleState.Calculating);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    /////////////////////////
    // performUpkeep       //
    /////////////////////////
    function testPerformUpkeepCanOnlyrunIfcheckUpkeepTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(raffleState == Raffle.RaffleState.Calculating);
    }

    function testPerfomUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentbalance = 0;
        uint256 numPlayers = 0;
        uint256 rafflestate = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentbalance,
                numPlayers,
                rafflestate
            )
        );

        raffle.performUpkeep("");
    }

    ///////////////////////////////////////////////////////////////////////
    modifier RaffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    //////////////////////////////////////////////////////
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        RaffleEnteredAndTimePassed
    {
        vm.recordLogs();

        raffle.performUpkeep("");

        Vm.Log[] memory entries = vm.getRecordedLogs(); // Log[] it is array of structs where topics is array in struct
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    //////////////////
    /// fulfillRandomWords////
    ///////////////////

    modifier skipfork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFullfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId // My first fuzz test
    ) public skipfork RaffleEnteredAndTimePassed {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAwinnerResetsSendsMoney()
        public
        RaffleEnteredAndTimePassed
        skipfork
    {
        uint256 additionalentrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalentrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 prize = entranceFee * (additionalentrants);
        ////////////////////////// Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Log[] it is array of structs where topics is array in struct
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimestamp = raffle.getLastTimestamp();
        //////////////////////////////////////// pretend chainlink vrf abd get anumber and winner;
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthPlayers() == 0);
        assert(previousTimestamp < raffle.getLastTimestamp());
        assert(raffle.getRecentWinner().balance == STARTING_BALANCE + prize);
    }
    /** In summary, integration tests focus on the correct integration and collaboration between internal components or modules of a system, while interaction tests concentrate on the interaction between a system and its external dependencies, such as databases, APIs, or third-party services.*/
}
