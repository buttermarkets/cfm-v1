// SPDX-License-Identifier: GPL-3.0-or-later
// TODO: rather use original contract + mockCall / mockFunction.
/* solhint-disable var-name-mixedcase, no-unused-vars */
pragma solidity 0.8.28;

import {IRealityETH} from "src/interfaces/IRealityETH.sol";

contract DummyRealityETH is IRealityETH {
    mapping(bytes32 => Question) public questions;

    function claimWinnings(
        bytes32 question_id,
        bytes32[] calldata history_hashes,
        address[] calldata addrs,
        uint256[] calldata bonds,
        bytes32[] calldata answers
    ) external override {
        // Mock implementation
    }

    function getFinalAnswerIfMatches(bytes32, bytes32, address, uint32, uint256)
        external
        pure
        override
        returns (bytes32)
    {
        return bytes32(0);
    }

    function getBounty(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function getArbitrator(bytes32) external pure override returns (address) {
        return address(0);
    }

    function getBond(bytes32) external pure override returns (uint256) {
        return 0;
    }

    function claimMultipleAndWithdrawBalance(
        bytes32[] calldata question_ids,
        uint256[] calldata lengths,
        bytes32[] calldata hist_hashes,
        address[] calldata addrs,
        uint256[] calldata bonds,
        bytes32[] calldata answers
    ) external override {
        // Mock implementation
    }

    function withdraw() external override {
        // Mock implementation
    }

    function submitAnswerReveal(bytes32 question_id, bytes32 answer, uint256 nonce, uint256 bond) external override {
        // Mock implementation
    }

    function setQuestionFee(uint256 fee) external override {
        // Mock implementation
    }

    function template_hashes(uint256) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function getContentHash(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function question_claims(bytes32)
        external
        pure
        override
        returns (address payee, uint256 last_bond, uint256 queued_funds)
    {
        return (address(0), 0, 0);
    }

    function fundAnswerBounty(bytes32 question_id) external payable override {
        // Mock implementation
    }

    function arbitrator_question_fees(address) external pure override returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure override returns (uint256) {
        return 0;
    }

    function askQuestion(
        uint256 template_id,
        string calldata question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce
    ) external payable override returns (bytes32) {
        return keccak256(abi.encodePacked(template_id, question, arbitrator, timeout, opening_ts, nonce));
    }

    function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous) external payable override {
        // Mock implementation
    }

    function submitAnswerFor(bytes32 question_id, bytes32 answer, uint256 max_previous, address answerer)
        external
        payable
        override
    {
        // Mock implementation
    }

    function isFinalized(bytes32) external pure override returns (bool) {
        return false;
    }

    function getHistoryHash(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function commitments(bytes32)
        external
        pure
        override
        returns (uint32 reveal_ts, bool is_revealed, bytes32 revealed_answer)
    {
        return (0, false, bytes32(0));
    }

    function createTemplate(string calldata) external pure override returns (uint256) {
        return 0;
    }

    function getBestAnswer(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function isPendingArbitration(bytes32) external pure override returns (bool) {
        return false;
    }

    function getOpeningTS(bytes32) external pure override returns (uint32) {
        return 0;
    }

    function getTimeout(bytes32 question_id) public view returns (uint32) {
        return questions[question_id].timeout;
    }

    function createTemplateAndAskQuestion(
        string calldata content,
        string calldata question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce
    ) external payable override returns (bytes32) {
        return keccak256(abi.encodePacked(content, question, arbitrator, timeout, opening_ts, nonce));
    }

    function getFinalAnswer(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function getFinalizeTS(bytes32) external pure override returns (uint32) {
        return 0;
    }

    function templates(uint256) external pure override returns (uint256) {
        return 0;
    }

    function resultFor(bytes32) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function submitAnswerCommitment(bytes32 question_id, bytes32 answer_hash, uint256 max_previous, address _answerer)
        external
        payable
        override
    {
        // Mock implementation
    }

    function notifyOfArbitrationRequest(bytes32 question_id, address requester, uint256 max_previous)
        external
        override
    {
        // Mock implementation
    }

    function submitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address answerer) external override {
        // Mock implementation
    }

    function assignWinnerAndSubmitAnswerByArbitrator(
        bytes32 question_id,
        bytes32 answer,
        address payee_if_wrong,
        bytes32 last_history_hash,
        bytes32 last_answer_or_commitment_id,
        address last_answerer
    ) external override {
        // Mock implementation
    }

    function cancelArbitration(bytes32 question_id) external override {
        // Mock implementation
    }

    function askQuestionWithMinBond(
        uint256 template_id,
        string memory question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 min_bond
    ) external payable virtual returns (bytes32) {
        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));
        bytes32 question_id =
            keccak256(abi.encodePacked(content_hash, arbitrator, timeout, min_bond, address(this), msg.sender, nonce));
        require(questions[question_id].timeout == 0, "question must not exist");
        questions[question_id].content_hash = content_hash;
        questions[question_id].arbitrator = arbitrator;
        questions[question_id].opening_ts = opening_ts;
        questions[question_id].timeout = timeout;
        return question_id;
    }

    function getMinBond(bytes32) external pure returns (uint256) {
        return 0;
    }

    function isSettledTooSoon(bytes32) external pure returns (bool) {
        return false;
    }

    function reopenQuestion(uint256, string calldata, address, uint32, uint32, uint256, uint256, bytes32)
        external
        payable
        returns (bytes32)
    {
        return bytes32(0);
    }

    function reopened_questions(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function reopener_questions(bytes32) external pure returns (bool) {
        return false;
    }

    function resultForOnceSettled(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }
}
