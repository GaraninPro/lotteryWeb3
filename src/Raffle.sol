// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A simple Raffle contract
 * @author Elliot Anderson
 * @notice This contract is for creating a simple raffle
 * @dev Implements ChainLink VRF
 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle_notEnoughEthSent();
    error Raffle_TransferFailed();
    error Raffle_RaffleNotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /** Type declaration */
    enum RaffleState {
        Open,
        Calculating
    }
    /** Variables */
    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;
    ///////////////////////////////////////////////
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    ///////////////////////////////////////////////
    address payable[] private s_players;
    address private s_recentWinner; // we do not write payable because we not gonna use this address as payable
    uint256 private s_lastTimeStamp;
    RaffleState private s_raffleState;

    /** Events */
    event enteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_interval = interval;
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.Open;
    }

    /**FUNCTIONS */
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle_notEnoughEthSent();
        }
        if (s_raffleState != RaffleState.Open) {
            revert Raffle_RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit enteredRaffle(msg.sender);
    }

    /////////////////////////////////////////////////////////////////
    function checkUpkeep(
        bytes memory /*checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* peformData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.Open == s_raffleState;
        bool hasMoney = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasMoney && hasPlayers);

        return (upkeepNeeded, "0x0");
    }

    ////////////////////////////////////////////////////////////////////
    function performUpkeep(bytes calldata /*peformData */) external {
        //a function is implementing an interface or overriding a method from a parent contract, and it has
        // to match the original function signature, even though not all parameters are used. : performData
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.Calculating;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATION,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    ////////////////////////////////////////////////////////////////////////////////
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    )
        internal
        override
    /**So, the requestId parameter in the fulfillRandomWords function is
     *  the same requestId that was returned when you called requestRandomWords.
     *  The randomWords parameter is the array of random numbers
     * generated by Chainlink VRF in response to your request.
     *
     * requestId is not used to fetch randomWords. Instead, requestId is an identifier
     * for a specific request for randomness. When a contract requests randomness
     * from the Chainlink VRF, the request is given a unique requestId. When the VRF has
     * generated the random numbers,
     *  it calls fulfillRandomWords with the requestId and the generated randomWords 4*/
    {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.Open;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);
        //Interactions
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
    }

    /**Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    ////////////////////////////////////////////////////////////
    function getNumWords() external pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() external pure returns (uint256) {
        return REQUEST_CONFIRMATION;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }
}
