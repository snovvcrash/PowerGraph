#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Inspired by:

https://wald0.com/?p=14 (by @andyrobbins)
https://github.com/HarmJ0y/TrustVisualizer (by @HarmJ0y)

Usage:

1. Generate graph.graphml with "python3 derivativeAdminVisualizer.py graph.csv".
2. Open graph.graphml in yEd Graph Editor (https://www.yworks.com/products/yed/download).
3. Select "Tools -> Fit Node to Label".
4. Select "Layout -> ..." of your choice (I prefer "Circular").

How to read the graph:

* Green edges (workstation -> user) mean that the user has an active session on a workstation.
* Red edges (user -> workstation) mean that the user has local admin privileges on a workstation.
* Blue dotted edges denote the shortest path from the source user to the target user.
"""

__author__  = '@snovvcrash'
__license__ = 'BSD-3-Clause'
__site__    = 'https://github.com/snovvcrash/PowerGraph'
__brief__   = 'Derivative admin graph visualizer'

import csv
from os.path import basename, splitext
from argparse import ArgumentParser

import pyyed

parser = ArgumentParser()
parser.add_argument('graph_file', help='graph file in .csv format (generate with PowerGraph.ps1)')
args = parser.parse_args()

if __name__ == '__main__':
	G = pyyed.Graph()

	with open(args.graph_file, 'r', encoding='utf-8') as fd:
		reader = csv.reader(fd, skipinitialspace=True, delimiter=',')
		next(reader, None)

		graph, path, distance = {}, [], -1
		for row in reader:
			# csv format: "NodeName","IsUser","Edges","Distance","Visited","Predecessor"

			nodeName = row[0]

			if int(row[3]) == distance + 1:
				path.append(nodeName)

			isUser = True if row[1].lower() == 'true' else False
			edges = row[2].split(',') if row[2] else []
			distance = int(row[3])
			predecessor = row[5]
			shape = 'roundrectangle' if isUser else 'rectangle'
			color = '#17e625' if isUser else '#e67873'

			graph[nodeName] = {
				'isUser': isUser,
				'edges': edges,
				'distance': distance,
				'predecessor': predecessor,
				'shape': shape,
				'color': color
			}

	for nodeName, nodeProperties in graph.items():
		try:
			G.add_node(
				nodeName,
				label=nodeName,
				shape=nodeProperties['shape'],
				shape_fill=nodeProperties['color']
			)
		except RuntimeWarning:
			pass

		for nodeEdgeName in nodeProperties['edges']:
			try:
				G.add_node(
					nodeEdgeName,
					label=nodeEdgeName,
					shape=graph[nodeEdgeName]['shape'],
					shape_fill=graph[nodeEdgeName]['color']
				)
			except RuntimeWarning:
				pass

			G.add_edge(
				nodeName,
				nodeEdgeName,
				color=graph[nodeEdgeName]['color'],
				width='2.0'
			)

	if len(path) > 1:
		for i in range(len(path)-1):
			G.add_edge(
				path[i],
				path[i+1],
				color='#0000ff',
				width='2.0',
				line_type='dotted'
			)

	G.write_graph(splitext(basename(args.graph_file))[0] + '.graphml')
