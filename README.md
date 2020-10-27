PowerGraph
==========

Based on [PowerPath](https://github.com/andyrobbins/PowerPath) (by [@andyrobbins](https://github.com/andyrobbins)), inspired by [TrustVisualizer](https://github.com/HarmJ0y/TrustVisualizer) (by [@HarmJ0y](https://github.com/HarmJ0y)), PowerGraph aims at finding the shortest path between two given AD users utilizing the Derivative Local Admin concept (by [@sixdub](https://github.com/sixdub)) and [PowerView 3.0](https://github.com/PowerShellMafia/PowerSploit/blob/dev/Recon/PowerView.ps1) (by [@HarmJ0y](https://github.com/HarmJ0y)) and visualizing the results. This concept is well-known and has been successfully applied in the [BloodHound](https://github.com/BloodHoundAD/BloodHound) project for years, so PowerGraph is just a training case.

Who is a derivative local admin? These two blog posts cover the topic in depth:

* [Derivative Local Admin. Intro | by Justin Warner | Medium](https://medium.com/@sixdub/derivative-local-admin-cdd09445aac8)
* [Automated Derivative Administrator Search – wald0.com](https://wald0.com/?p=14)

I'm just gonna give the basic idea with an example below.

## A Derivative Local Admin

Consider the following graph:

<p align="center"><img src="https://raw.githubusercontent.com/snovvcrash/PowerGraph/main/example/graph.png" alt="graph.png"></p>

* green edges (workstation → user) mean that the user has an active session on a workstation;
* red edges (user → workstation) mean that the user has local admin privileges on a workstation.

A domain user is a derivative local admin of a workstation if she is able to compromise the credentials of any other user, who has legitimate administrative privileges with respect to this workstation, performing the process of lateral movement. As simple as that.

In terms of our example (see the graph above), `mallory` is a derivative local admin of workstation `PC003` because she can dump `david`'s credentials through the intermediate workstation `PC002`. The blue dotted edges denote the shortest path to get `david`'s access level starting as the `mallory` user.

## What Is PowerGraph and How It Works

PowerGraph is a successor of the [PowerPath](https://github.com/andyrobbins/PowerPath) PoC script by [@andyrobbins](https://github.com/andyrobbins) which uses PowerView 3.0 under the hood (vs PowerView 2.0 in PowerPath) and comes with a simple Python tool for generating `.graphml` visualizations.

It requires:

* [PowerView 3.0](https://github.com/PowerShellMafia/PowerSploit/blob/dev/Recon/PowerView.ps1) to enumerate the AD domain;
* Python 3 and [pyyed](https://github.com/jamesscottbrown/pyyed) to generate the `.graphml` file;
* [yEd Graph Editor](https://www.yworks.com/products/yed/download) to visualize the graph.

What is `PowerGraph.ps1` actually doing with the help of PowerView:

1. Enumerates domain users and computers (`Get-DomainUser`, `Get-DomainComputer`).
2. Enumerates active user sessions on every computer in the AD environment (`Get-NetSession` / `Get-NetRDPSession`).
3. Enumerates domain users with local admin rights on computers with active sessions (`Get-NetLocalGroupMember`, `Get-DomainGroupMember`).
4. Ties it all together and builds a graph.
5. Uses [Dijkstra's algorithm](https://en.wikipedia.org/wiki/Dijkstra%27s_algorithm) to find the shortest path from a source user (potential derivative admin) to the target user if there is one.

Further, an attacker can dump a chain of credentials from memory on intermediate workstations and pwn the target user.

Note: the resulting graph does not show all the workstations that the users may have administrative access to, but only those that have active sessions at the moment.

## Usage Example

Load the necessary scripts using any method you want.

```
PS > IEX(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/dev/Recon/PowerView.ps1')
PS > IEX(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/snovvcrash/PowerGraph/main/PowerGraph.ps1')
```

Build a graph and find the shortest path from source to target user. Export the results as a `.csv` file.

```
PS > Find-DerivativeAdminPath -Source mallory -Target david -Raw | Export-CSV -NoTypeInformation graph.csv
```

Generate a `.graphml` file with the Python script.

```
$ sudo python3 -m pip install -r requirements.txt
$ python3 derivativeAdminVisualizer.py graph.csv
```

Import the `.graphml` file into yEd Graph Editor. Then adjust the graph representation as follows:

1. Select "Tools → Fit Node to Label".
2. Select "Layout → ..." of your choice (I prefer "Circular" layout).

Alternatively, `Find-DerivativeAdminPath` can be used to show the shortest path right in the PowerShell console without graph visualization.

```
PS > Find-DerivativeAdminPath -Source mallory -Target david -Ping

NodeName             IsUser ComputerIP
--------             ------ ----------
mallory                True
PC002.megacorp.local  False 10.10.13.37
david                  True
```
