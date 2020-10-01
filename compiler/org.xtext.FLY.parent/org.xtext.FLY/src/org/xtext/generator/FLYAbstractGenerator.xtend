package org.xtext.generator

import java.util.HashMap
import java.util.List
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.xtext.fLY.VariableDeclaration
import org.xtext.fLY.DeclarationObject
import org.xtext.fLY.Expression
import org.xtext.fLY.BlockExpression

/**
 * The {@code FLYAbstractGenerator} abstract class gathers common FLY generators
 * members.
 * 
 * @author Simone Bisogno
 */
abstract class FLYAbstractGenerator extends AbstractGenerator {

	protected var typeSystem = new HashMap<String, HashMap<String, String>> // memory hash
	/**
	 * This map retains information about every declared array dimensions
	 */
	protected var arraySystem = new HashMap<String, HashMap<String, List<String>>>
	protected var listEnvironment = #["smp", "aws", "aws-debug", "azure"]
	protected var idExecution = System.currentTimeMillis
	protected var fileName = ""
	protected var graphMethodsReturnTypes = initializeGraphMethodsReturnTypes
	protected var res = null as Resource
	protected var isLocal = true

	override void doGenerate(
		Resource input,
		IFileSystemAccess2 fsa,
		IGeneratorContext context
	)

	def CharSequence generateBlockExpression(BlockExpression exp, String scope, boolean local)

	def CharSequence generateExpression(Expression element, String scope, boolean local)

	def generateForBodyExpression(Expression body, String scope, boolean local) '''
		«IF body instanceof BlockExpression»
			«generateBlockExpression(body, scope, local)»
		«ELSE»
			«generateExpression(body, scope, local)»
		«ENDIF»
	'''

	/**
	 * {@code checkDeclaration(Resource, String)} checks whether a declaration
	 * of given type lies among the ones within given resource.
	 * 
	 * @param resource The resource containing all declarations
	 * @param type The type of declaration looked for
	 * @return {@code true} if a declaration of given type is present,
	 * {@code false} otherwise
	 */
	protected def checkDeclaration(
		Resource resource,
		String type
	) {
		for (
			VariableDeclaration env: resource
			.allContents
			.toIterable
			.filter(VariableDeclaration)
			.filter[right instanceof DeclarationObject]
			.filter[(right as DeclarationObject).features.get(0).value_s.equals(type)]
		) {
			return true
		}
		return false
	}

	/**
	 * {@code indexedObjectNumDims(String)} determines whether given
	 * {@code IndexObject} type is an array, a 2D matrix or a 3D matrix and returns
	 * the number of dimensions accordingly
	 * 
	 * @param type The type of {@code IndexedObject}
	 * @return The number of dimensions of given {@code IndexObject}
	 * @throws IllegalArgumentException if given type is not {@code IndexObject}
	 * @see org.xtext.fLY.IndexObject IndexObject
	 */
	protected def indexObjectNumDims(String type) {
		// check whether positions are positive
		val firstOcc = type.indexOf("[]")
		val lastOcc = type.lastIndexOf("[]")
		if (firstOcc < 0 || lastOcc < 0) {
			throw new IllegalArgumentException(
				'''«type» is not a valid type!'''
			)
		}

		val numDims = lastOcc - firstOcc
//		println('''Dimensions calculation for «type» is «numDims»''')
		switch numDims {
			case 0: 1
			case 2: 2
			case 4: 3
		}
	}

	/**
	 * {@code initializeGraphMethodsReturnTypes()} creates a map of return types
	 * for graph methods; keys are graph method names, values are their return
	 * types.
	 */
	private def initializeGraphMethodsReturnTypes() {
		#{
			"clear" -> "Graph",
			"addNode" -> "Graph",
			"addNodes" -> "Graph",
			"nodeDegree" -> "Integer",
			"nodeInDegree" -> "Integer",
			"nodeOutDegree" -> "Integer",
			"neighbourhood" -> "Graph",
			"nodeEdges" -> "Object[]",
			"nodeInEdges" -> "Object[]",
			"nodeOutEdges" -> "Object[]",
			"nodeSet" -> "Object[]",
			"numNodes" -> "Integer",
			"hasNode" -> "Boolean",
			"addEdge" -> "Graph",
			"getEdge" -> "Object",
			"edgeSet" -> "Object[]",
			"numEdges" -> "Integer",
			"getEdgeSource" -> "Object",
			"getEdgeTarget" -> "Object",
			"getEdgeWeight" -> "Double",
			"hasEdge" -> "Boolean",
			"shortestPath" -> "Object[]",
			"shortestPathLength" -> "Integer",
			"getDiameter" -> "Double",
			"getRadius" -> "Double",
			"getCenter" -> "Object[]",
			"getPeriphery" -> "Object[]",
			"getNodeEccentricity" -> "Double",
			"getAverageClusteringCoefficient" -> "Double",
			"getGlobalClusteringCoefficient" -> "Double",
			"getNodeClusteringCoefficient" -> "Double",
			"getLCA" -> "Object",
			"bfsEdges" -> "Object[]",
			"bfsNodes" -> "Object[]",
			"bfsTree" -> "Graph",
			"dfsEdges" -> "Object[]",
			"dfsNodes" -> "Object[]",
			"dfsTree" -> "Graph",
			"isConnected" -> "Boolean",
			"isStronglyConnected" -> "Boolean",
			"connectedComponents" -> "Object[]",
			"connectedSubgraphs" -> "Graph[]",
			"numberConnectedComponents" -> "Integer",
			"nodeConnectedComponent" -> "Object[]",
			"stronglyConnectedComponents" -> "Object[]",
			"stronglyConnectedSubgraphs" -> "Graph[]",
			"isDAG" -> "Boolean",
			"topologicalSort" -> "Object[]",
			"getMST" -> "Graph"
		}
	}

	/**
	 * {@code isURL(String)} checks whether given file path starts with 'http',
	 * 'https', 'ftp', 'ftps' ot 'sftp' and is a valid URL.
	 * 
	 * @param path The file path to check
	 * @see <a href="https://stackoverflow.com/a/3809435/5674302" target="_top">
	 * What is a good regular expression to match a URL?
	 * - StackOverflow question
	 * </a>
	 */
	protected def isURL(String path) {
		val httpUrlRegExp = "^((ht|f)tps?|sftp):\\/\\/(www\\.)?[-a-zA-Z0-9@:%._\\+~#=]{2,256}\\.[a-z]{2,63}\\b([-a-zA-Z0-9@:%_\\+.~#?&//=]*)"
		return path.matches(httpUrlRegExp)
	}

}