function Find-DerivativeAdminPath {
<#

.SYNOPSIS

Finds the shortest path between two given AD users.

Author: @snovvcrash, @andyrobbins
Kudos: @andyrobbins, @harmj0y, @sixdub, @jwtruher
License: BSD-3-Clause
Requires: Powerview 3.0

.DESCRIPTION

1. Enumerate domain users and computers.
2. Enumerate active user sessions on every computer in the AD environment.
3. Enumerate domain users with local admin rights on computers with active sessions.
4. Tie it all together and build a graph.
5. Use Dijkstra's algorithm to find the shortest path from a source user (potential derivative admin) to the target user.
[6.] Dump credentials from memory.
[7.] Pwn the target user.

.PARAMETER Source

Name of the source user (potential derivative admin).

.PARAMETER Target

Name of the target user you're hunting.

.PARAMETER Method

PowerView method to query for active sessions (either Get-NetSesssion or Get-NetRDPSession).

.PARAMETER Group

Name of the admin group which members are enumerated during the Get-NetLocalGroupMember phase.

.PARAMETER Ping

Switch. Ping each host to ensure it's up before enumerating.

.PARAMETER Raw

Switch. Print raw resulting graph (use with Export-CSV pipe).

.EXAMPLE

PS > Find-DerivativeAdminPath -Source mallory -Target david

.EXAMPLE

PS > Find-DerivativeAdminPath -Source mallory -Target david -Method NetRDPSession -Group Администраторы -Ping | Ft

.EXAMPLE

PS > Find-DerivativeAdminPath -Source mallory -Target david -Raw | Export-CSV -NoTypeInformation graph.csv
$ python3 derivativeAdminVisualizer.py graph.csv

#>

	[CmdletBinding()]
	[OutputType([System.Array])]

	PARAM (
		[Parameter(Mandatory = $true)]
		[String]
		$Source,

		[Parameter(Mandatory = $true)]
		[String]
		$Target,

		[ValidateSet('NetSession', 'NetRDPSession')]
		[String]
		$Method = 'NetSession',

		[String]
		$Group = 'Administrators',

		[Switch]
		$Ping,

		[Switch]
		$Raw
	)

	BEGIN {
		$Graph = @()
		$Infinity = [int]::MaxValue

		$DomainUsers = Get-DomainUser | ForEach-Object {$_.SamAccountName}

		ForEach ($User in $DomainUsers) {
			$Vertex = New-Object PSObject
			$Vertex | Add-Member NoteProperty 'NodeName' $User
			$Vertex | Add-Member NoteProperty 'IsUser' $True
			$Vertex | Add-Member NoteProperty 'Edges' @()
			$Vertex | Add-Member NoteProperty 'Distance' $Infinity
			$Vertex | Add-Member NoteProperty 'Visited' $False
			$Vertex | Add-Member NoteProperty 'Predecessor' $Null
			$Graph += $Vertex
		}

		If ($Ping) {
			$DomainComputers = Get-DomainComputer -Ping | ForEach-Object {$_.DnsHostName}
		}
		Else {
			$DomainComputers = Get-DomainComputer | ForEach-Object {$_.DnsHostName}
		}

		ForEach ($Computer in $DomainComputers) {
			$Vertex = New-Object PSObject
			$Vertex | Add-Member NoteProperty 'NodeName' $Computer
			$Vertex | Add-Member NoteProperty 'IsUser' $False
			$Vertex | Add-Member NoteProperty 'Edges' @()
			$Vertex | Add-Member NoteProperty 'Distance' $Infinity
			$Vertex | Add-Member NoteProperty 'Visited' $False
			$Vertex | Add-Member NoteProperty 'Predecessor' $Null
			$Graph += $Vertex
		}
	}

	PROCESS {
		$DomainComputers | ForEach-Object {
			If ($Method -Eq 'NetSession') {
				$Session = Get-NetSession -ComputerName $_
			}
			ElseIf ($Method -Eq 'NetRDPSession') {
				$Session = Get-NetRDPSession -ComputerName $_
			}

			$Session | ForEach-Object {
				$ComputerName = $_.ComputerName
				$LoggedOnUser = $_.UserName.split('\')[-1]
				$CurrentNode = $Graph | Where-Object {$_.NodeName -Contains $ComputerName}

				If ($CurrentNode -And $LoggedOnUser -And $CurrentNode.Edges -NotContains $LoggedOnUser) {
					$CurrentNode.Edges += $LoggedOnUser
				}

				$LocalGroupMembers = Get-NetLocalGroupMember -ComputerName $ComputerName -Group $Group | Where-Object {$_.IsDomain} | Select-Object MemberName, IsGroup
				$Admins = $LocalGroupMembers | Where-Object {!$_.IsGroup} | ForEach-Object {$_.MemberName}
				$AdminGroups = $LocalGroupMembers | Where-Object {$_.IsGroup} | ForEach-Object {$_.MemberName}

				ForEach ($AdminGroup in $AdminGroups) {
					$Admins += Get-DomainGroupMember -Identity $AdminGroup -Recurse | Where-Object {$_.MemberObjectClass -Eq 'user'} | ForEach-Object {$_.MemberName}
				}

				ForEach ($Admin in $Admins) {
					$CurrentNode = $Graph | Where-Object {$_.NodeName -Contains $Admin.split('\')[-1]}
					If ($CurrentNode -And $CurrentNode.Edges -NotContains $ComputerName) {
						$CurrentNode.Edges += $ComputerName
					}
				}
			}
		}

		# Dijkstra's algorithm (based on work by James Truher: https://jtruher3.wordpress.com/2006/10/16/dijkstra)

		$SourceNode = $Graph | Where-Object {$_.NodeName -Contains $Source}
		$SourceNode.Distance = 0
		$TargetNode = $Graph | Where-Object {$_.NodeName -Contains $Target}

		For ($i = 0; $i -LT $Graph.Length; $i++) {
			$CurrentNode = $Graph | Where-Object {!$_.Visited} | Sort-Object Distance | Select-Object -First 1
			
			For ($j = 0; $j -LT $CurrentNode.Edges.Count; $j++) {
				$CurrentNodeEdge = $Graph | Where-Object {$CurrentNode.Edges[$j] -Contains $_.NodeName}
				If ($CurrentNodeEdge.Distance -GT $CurrentNode.Distance + 1) {
					$CurrentNodeEdge.Distance = $CurrentNode.Distance + 1
					$CurrentNodeEdge.Predecessor = $CurrentNode
				}
			}
			
			$CurrentNode.Visited = $True
		}

		If ($TargetNode.Distance -LT $Infinity) {
			If ($Raw) {
				For ($i = 0; $i -LT $Graph.Length; $i++) {
					$Graph[$i].Edges = $Graph[$i].Edges -Join ','
					If ($Graph[$i].Predecessor) {
						$Graph[$i].Predecessor = $Graph[$i].Predecessor.NodeName
					}
				}
				$Graph = $Graph | Sort-Object Distance
				$Graph
			}
			Else {
				$CurrentNode = $TargetNode
				$Path = @()
				For ($i = 0; $i -LT $TargetNode.Distance; $i++) {
					$PathLink = New-Object PSObject
					$PathLink | Add-Member NoteProperty 'NodeName' $($CurrentNode.Predecessor).NodeName
					$PathLink | Add-Member NoteProperty 'IsUser' $($CurrentNode.Predecessor).IsUser

					If (!$PathLink.IsUser) {
						$ComputerIP = [System.Net.Dns]::GetHostAddresses($PathLink.NodeName) | % {$_.IPAddressToString}
						$PathLink | Add-Member NoteProperty 'ComputerIP' $ComputerIP
					}
					Else {
						$PathLink | Add-Member NoteProperty 'ComputerIP' $Null
					}

					$Path += $PathLink
					$CurrentNode = $CurrentNode.Predecessor
				}

				[System.Array]::Reverse($Path)
				$PathLink = New-Object PSObject
				$PathLink | Add-Member NoteProperty 'NodeName' $TargetNode.NodeName
				$PathLink | Add-Member NoteProperty 'IsUser' $TargetNode.IsUser

				If (!$PathLink.IsUser) {
					$ComputerIP = [System.Net.Dns]::GetHostAddresses($PathLink.NodeName) | % {$_.IPAddressToString}
					$PathLink | Add-Member NoteProperty 'ComputerIP' $ComputerIP
				}
				Else {
					$PathLink | Add-Member NoteProperty 'ComputerIP' $Null
				}

				$Path += $PathLink
				$Path
			}
		}
	}
}
