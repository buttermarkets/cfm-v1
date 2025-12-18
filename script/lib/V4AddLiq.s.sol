// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./V4AddLiqBase.s.sol";

/// @title V4AddLiq
/// @notice Uniswap v4 liquidity utilities for long/short (IF<>LONG, IF<>SHORT) pools.
/// @dev Inherits common utilities from V4AddLiqBase. Uses symmetric deposit amounts.
///      Semantic price: P = outcomeToken / (longToken|shortToken) (numeraire/quoted)
abstract contract V4AddLiq is V4AddLiqBase {
    /// @notice Extended config for long/short pools with price band
    struct Cfg {
        BaseCfg base;
        uint256 minP1e18; // min price (numeraire/quoted), 0 for full range
        uint256 maxP1e18; // max price (numeraire/quoted), 0 for full range
    }

    // ===== Config parsing =====

    function _parseV4Cfg(string memory json) internal returns (Cfg memory cfg) {
        cfg.base = _parseBaseCfg(json);
        (cfg.minP1e18, cfg.maxP1e18) = _parseOptionalBand(json, ".minP1e18", ".maxP1e18");
    }

    function _parseDepositAmount(string memory json) internal pure returns (uint256) {
        return vm.parseJsonUint(json, ".depositAmount");
    }

    function _parseSlippagePct(string memory json) internal pure returns (uint256) {
        return vm.parseJsonUint(json, ".slippagePct");
    }

    // ===== Permit2 approvals (3-token version for long/short) =====

    function _approvePermit2(
        Cfg memory cfg,
        address outcomeToken,
        address shortToken,
        address longToken,
        uint256 amount,
        uint48 expiration
    ) internal {
        _requirePermit2Amount(amount);
        IERC20(outcomeToken).approve(cfg.base.permit2, amount);
        IERC20(shortToken).approve(cfg.base.permit2, amount);
        IERC20(longToken).approve(cfg.base.permit2, amount);
        IAllowanceTransfer(cfg.base.permit2).approve(outcomeToken, cfg.base.positionManager, uint160(amount), expiration);
        IAllowanceTransfer(cfg.base.permit2).approve(shortToken, cfg.base.positionManager, uint160(amount), expiration);
        IAllowanceTransfer(cfg.base.permit2).approve(longToken, cfg.base.positionManager, uint160(amount), expiration);
    }

    // Backward-compatible overload for 2-token flows (legacy 1-pool script)
    function _approvePermit2(
        Cfg memory cfg,
        address outcomeToken,
        address scalarToken,
        uint256 amount,
        uint48 expiration
    ) internal {
        _requirePermit2Amount(amount);
        IERC20(outcomeToken).approve(cfg.base.permit2, amount);
        IERC20(scalarToken).approve(cfg.base.permit2, amount);
        IAllowanceTransfer(cfg.base.permit2).approve(outcomeToken, cfg.base.positionManager, uint160(amount), expiration);
        IAllowanceTransfer(cfg.base.permit2).approve(scalarToken, cfg.base.positionManager, uint160(amount), expiration);
    }

    // ===== High level helpers =====

    /// @notice Mint liquidity for a long/short pair
    /// @dev Splits deposit 50/50 between two pools with complementary price bands
    /// @param cfg Config with price band
    /// @param outcomeToken The outcome (IF) token (numeraire)
    /// @param shortToken The short token (quoted for short pool)
    /// @param longToken The long token (quoted for long pool)
    /// @param deposit Total deposit amount (split 50/50)
    /// @param recipient LP token recipient
    /// @param deadline Transaction deadline
    function _mintForPair(
        Cfg memory cfg,
        address outcomeToken,
        address shortToken,
        address longToken,
        uint256 deposit,
        address recipient,
        uint256 deadline
    ) internal {
        // Split deposit 50/50 between two pools
        uint256 depositPerPool = deposit / 2;

        console.log("=== Adding liquidity to 2 pools ===");
        console.log("Total deposit:", deposit);
        console.log("Per pool:", depositPerPool);

        // Pool 1: outcome <> long with [minP, maxP]
        // Semantic: P = outcome / long
        console.log("\n--- Pool 1: outcome <> long ---");
        _mintSinglePool(cfg, outcomeToken, longToken, cfg.minP1e18, cfg.maxP1e18, depositPerPool, recipient, deadline);

        // Pool 2: outcome <> short with complementary [1-maxP, 1-minP]
        // Semantic: P = outcome / short
        console.log("\n--- Pool 2: outcome <> short ---");
        uint256 minPForShort = (cfg.minP1e18 == 0 && cfg.maxP1e18 == 0) ? 0 : 1e18 - cfg.maxP1e18;
        uint256 maxPForShort = (cfg.minP1e18 == 0 && cfg.maxP1e18 == 0) ? 0 : 1e18 - cfg.minP1e18;
        _mintSinglePool(cfg, outcomeToken, shortToken, minPForShort, maxPForShort, depositPerPool, recipient, deadline);
    }

    // Backward-compatible overload for legacy 2-token single-pool scripts.
    function _mintForPair(
        Cfg memory cfg,
        address outcomeToken,
        address scalarToken,
        uint256 deposit,
        address recipient,
        uint256 deadline
    ) internal {
        _mintSinglePool(cfg, outcomeToken, scalarToken, cfg.minP1e18, cfg.maxP1e18, deposit, recipient, deadline);
    }

    /// @notice Mint liquidity for a single outcome<>scalar pool (symmetric amounts)
    /// @dev Wrapper around _mintSinglePoolSemantic with symmetric deposit amounts
    /// @param cfg Config
    /// @param outcomeToken The outcome token (numeraire)
    /// @param scalarToken The scalar token (long or short) (quoted)
    /// @param minP Min semantic price (outcome/scalar)
    /// @param maxP Max semantic price (outcome/scalar)
    /// @param deposit Deposit amount (used for both tokens)
    /// @param recipient LP token recipient
    /// @param deadline Transaction deadline
    function _mintSinglePool(
        Cfg memory cfg,
        address outcomeToken,
        address scalarToken,
        uint256 minP,
        uint256 maxP,
        uint256 deposit,
        address recipient,
        uint256 deadline
    ) internal {
        // Semantic: P = numeraire / quoted = outcomeToken / scalarToken
        _mintSinglePoolSemantic(
            cfg.base,
            scalarToken, // tokenQuoted
            outcomeToken, // tokenNumeraire
            minP,
            maxP,
            deposit, // amountQuotedMax
            deposit, // amountNumeraireMax
            recipient,
            deadline
        );
    }
}
