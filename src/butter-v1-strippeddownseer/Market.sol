// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "./RealityProxy.sol";

contract Market {
    /// @dev Flag to initialize the market only once.
    bool public initialized;

    /// @dev Contains the information associated to Reality.
    /// @param questionsIds Reality questions ids.
    /// @param templateId Reality templateId.
    /// @param encodedQuestions Encoded questions parameters, needed to create and reopen a question.
    struct RealityParams {
        bytes32 questionId;
        uint256 templateId;
        string[] encodedQuestions;
    }

    /// @dev Contains the information associated to Conditional Tokens.
    /// @param conditionId Conditional Tokens conditionId.
    /// @param parentCollectionId Conditional Tokens parentCollectionId.
    /// @param parentOutcome Conditional outcome to use (optional).
    /// @param questionId Conditional Tokens questionId.
    /// @param wrapped1155 Outcome tokens Wrapped1155 address.
    /// @param data Wrapped1155 token data.
    struct ConditionalTokensParams {
        bytes32 conditionId;
        bytes32 parentCollectionId;
        uint256 parentOutcome;
        bytes32 questionId;
        IERC20[] wrapped1155;
        bytes[] data;
    }

    /// @dev The name of the market.
    string public marketName;
    /// @dev The market outcomes, doesn't include the INVALID_RESULT outcome.
    string[2] public outcomes = ["UP", "DOWN"];
    /// @dev Lower bound, only used for scalar markets.
    uint256 public lowerBound;
    /// @dev Upper bound, only used for scalar markets.
    uint256 public upperBound;
    /// @dev Conditional Tokens parameters.
    ConditionalTokensParams public conditionalTokensParams;
    /// @dev Reality parameters.
    RealityParams public realityParams;
    /// @dev Oracle contract.
    RealityProxy public realityProxy;

    /// @dev Initializer.
    /// @param _marketName The name of the market.
    /// @param _lowerBound Lower bound, only used for scalar markets.
    /// @param _upperBound Upper bound, only used for scalar markets.
    /// @param _conditionalTokensParams Conditional Tokens params.
    /// @param _realityParams Reality params.
    /// @param _realityProxy Oracle contract.
    function initialize(
        string memory _marketName,
        uint256 _lowerBound,
        uint256 _upperBound,
        ConditionalTokensParams memory _conditionalTokensParams,
        RealityParams memory _realityParams,
        RealityProxy _realityProxy
    ) external {
        require(!initialized, "Already initialized.");

        marketName = _marketName;
        lowerBound = _lowerBound;
        upperBound = _upperBound;
        conditionalTokensParams = _conditionalTokensParams;
        realityParams = _realityParams;
        realityProxy = _realityProxy;

        initialized = true;
    }

    /// @dev The templateId associated to the Reality question.
    /// @return The template id.
    function templateId() external view returns (uint256) {
        return realityParams.templateId;
    }

    /// @dev Returns the Reality questions ids. Multi Scalar markets have one question for each outcome, while any other market has only one question.
    /// @return The Reality questions ids.
    function questionsId() external view returns (bytes32) {
        return realityParams.questionId;
    }

    /// @dev Encoded questions parameters, needed to create and reopen a question.
    /// @param index The question index.
    /// @return The encoded question.
    function encodedQuestions(uint256 index) external view returns (string memory) {
        return realityParams.encodedQuestions[index];
    }

    /// @dev Conditional Tokens questionId.
    /// @return the question ID.
    function questionId() external view returns (bytes32) {
        return conditionalTokensParams.questionId;
    }

    /// @dev Conditional Tokens conditionId.
    /// @return The condition ID.
    function conditionId() external view returns (bytes32) {
        return conditionalTokensParams.conditionId;
    }

    /// @dev Conditional Tokens parentCollectionId.
    /// @return The parent collection ID.
    function parentCollectionId() external view returns (bytes32) {
        return conditionalTokensParams.parentCollectionId;
    }

    /// @dev The parent outcome (optional). The parent market's outcome token this market redeems for.
    /// @return The parent outcome index.
    function parentOutcome() external view returns (uint256) {
        return conditionalTokensParams.parentOutcome;
    }

    /// @dev Returns the wrapped1155 and the data corresponding to an outcome token.
    /// @param index The outcome index.
    /// @return wrapped1155 The wrapped token.
    /// @return data The token data.
    function wrappedOutcome(uint256 index) external view returns (IERC20 wrapped1155, bytes memory data) {
        return (conditionalTokensParams.wrapped1155[index], conditionalTokensParams.data[index]);
    }

    /// @dev Returns the number of outcomes.
    /// Doesn't include the INVALID_RESULT outcome.
    /// @return numOutcomes The number of outcomes.
    function numOutcomes() external view returns (uint256) {
        return 2;
    }

    /// @dev Helper function to resolve the market.
    function resolve() external {
        realityProxy.resolve(this);
    }
}
