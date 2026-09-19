# ASEN-Capstone-Green
This repository houses all software for a Small Space Debris Detection and Tracking Satellite for the CU Boulder ASEN Senior Capstone Projects 2026-27 class, specifically the Green Team. 

# 0. Table of Contents
0. [Table of Contents](#0-table-of-contents)
1. [Getting Started](#1-getting-started)
    * [1.1: Cloning the Repo](#11-cloning-the-repository-to-your-local-machine)
2. [Ground Software](#2-ground-software)
    * [Ground Communications Stack](#21-ground-communications-stack)
    * [Ground Data Processing Stack](#22-ground-data-processing-stack)
3. [Systems, Integraton, and Testing](#3-systems-integration-and-testing)
4. [Simulation and Modeling](#4-simulation-and-modeling)

# 1. Getting Started
> If you don't know much about Git/GitHub and would like to learn, there are a bunch of resources online, but I also made a repository which can sorta serve as a reference/starting point for a lot of the important workflow. If that sounds like it might be useful, you can access it at [https://github.com/bassett-luke/GitHub-Reference](https://github.com/bassett-luke/GitHub-Reference), let me know if y'all have any problems with any of the commands/instructions. -Luke

## 1.1 Cloning the Repository to Your Local Machine
If you want just the flight software repository (e.g. deployment on flight computer), go to [https://github.com/ASEN-Capstone-Green/asen4018-green-fsw](https://github.com/ASEN-Capstone-Green/asen4018-green-fsw), and follow the cloning instructions there (TODO). 

Since we're using Git Submodules (section about that not included in the reference (yet)), we have a little bit different workflow for pulling the files down than a standard `git clone`. You have the following two options:

1. If you're looking to just work on simulation, analysis, or ground data processing, and you don't need to work on flight software at all, you can clone just this repository like normal:

```shell
git clone https://github.com/ASEN-Capstone-Green/ASEN-Capstone-Green
```

2. To pull down the FULL software stack (this master repository plus the flight software repository), run the following to pull down the current manifest: 

```shell
git clone --recurse-submodules https://github.com/ASEN-Capstone-Green/ASEN-Capstone-Green
```

If you pulled down just this repository without the flight software, you should already have an empty **asen4018-green-fsw** repo, so you just need to run the following to pull in the flight software:

```shell
git submodule update --init --recursive
```

## 1.2 Workflow
> Message me on Teams and I can give you commit access to these repositories! -Luke

### 1.2.1 Main Repository Workflow

### 1.2.2 Flight Software Repository Workflow
Submodules and tags


# 2. Ground Software

## 2.1 Ground Communications Stack

### 2.1.1 Ground Interface and Command Reference
See [Uplink Packet Format](#212-uplink-packet-format) and [Science Packet Format](#222-science-packet-format). 

### 2.1.2 Uplink Packet Format
TODO

### 2.1.3 Telemetry Packet Format


## 2.2 Ground Data Processing Stack

### 2.2.1 Ground Data Systems

### 2.2.2 Science Packet Format
TODO


# 3. Systems, Integration, and Testing

# 4. Simulation and Modeling
