# LemonJet Sui Contracts

This project contains the Sui Move contracts for LemonJet, a decentralized gaming application.

## Overview

LemonJet is a simple and fair game of chance where players can bet their Sui tokens and have a chance to win a payout based on a chosen coefficient. The contracts are designed to be transparent and secure, with all game logic and fund management handled on-chain.

The project is divided into three main modules:

*   **`lemonjet`**: The main game logic, including the `play` function.
*   **`vault`**: The contract that manages the game's funds, allowing users to deposit and withdraw assets.
*   **`shares`**: A utility contract for managing shares in the vault.

## Modules

### `lemonjet`

This module contains the core game logic. The main function is `play`, which takes the following arguments:

*   `random`: A `Random` object for generating random numbers.
*   `stake`: The amount of tokens to bet.
*   `coef`: The desired payout coefficient.
*   `vault`: The `Vault` object to use for the game.
*   `ctx`: The transaction context.

The `play` function generates a random number and compares it to a threshold calculated from the `coef`. If the random number is less than or equal to the threshold, the player wins and receives a payout.

### `vault`

This module defines a `Vault` that holds the game's assets. The vault allows users to deposit and withdraw funds, and it also manages the minting and burning of shares. The vault has a fee mechanism that collects a small percentage of each bet.

### `shares`

This module defines a `Shares` object that represents a share in the vault. The `Shares` object can be used to redeem assets from the vault.

## Usage

To play the game, you need to call the `play` function in the `lemonjet` module. You will need to provide a `Random` object, the amount of tokens you want to bet, the desired payout coefficient, and the `Vault` object.

To deposit funds into the vault, you can call the `deposit` function in the `vault` module. This will mint you a corresponding amount of shares.

To withdraw funds from the vault, you can call the `redeem` function in the `vault` module. This will burn your shares and return you the corresponding amount of assets.

## Disclaimer

This is a proof of concept and has not been audited. Use at your own risk.
