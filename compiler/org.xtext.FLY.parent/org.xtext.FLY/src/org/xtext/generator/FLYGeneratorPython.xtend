package org.xtext.generator

import java.util.ArrayList
import java.util.Arrays
import java.util.HashMap
import java.util.HashSet
import java.util.List
import java.util.Map
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.xtext.fLY.ArithmeticExpression
import org.xtext.fLY.Assignment
import org.xtext.fLY.BinaryOperation
import org.xtext.fLY.BlockExpression
import org.xtext.fLY.BooleanLiteral
import org.xtext.fLY.CastExpression
import org.xtext.fLY.ChannelReceive
import org.xtext.fLY.ChannelSend
import org.xtext.fLY.DatTableObject
import org.xtext.fLY.DeclarationObject
import org.xtext.fLY.Expression
import org.xtext.fLY.FloatLiteral
import org.xtext.fLY.ForExpression
import org.xtext.fLY.FunctionDefinition
import org.xtext.fLY.FunctionReturn
import org.xtext.fLY.IfExpression
import org.xtext.fLY.IndexObject
import org.xtext.fLY.LocalFunctionCall
import org.xtext.fLY.LocalFunctionInput
import org.xtext.fLY.MathFunction
import org.xtext.fLY.NameObject
import org.xtext.fLY.NameObjectDef
import org.xtext.fLY.NativeExpression
import org.xtext.fLY.NumberLiteral
import org.xtext.fLY.ParenthesizedExpression
import org.xtext.fLY.PrintExpression
import org.xtext.fLY.RangeLiteral
import org.xtext.fLY.RequireExpression
import org.xtext.fLY.SortExpression
import org.xtext.fLY.StringLiteral
import org.xtext.fLY.TimeFunction
import org.xtext.fLY.UnaryOperation
import org.xtext.fLY.VariableDeclaration
import org.xtext.fLY.VariableFunction
import org.xtext.fLY.VariableLiteral
import org.xtext.fLY.WhileExpression
import org.xtext.fLY.PostfixOperation
import org.xtext.fLY.ArrayDefinition
import org.xtext.fLY.FlyFunctionCall
import org.xtext.fLY.EnvironemtLiteral
import org.eclipse.xtext.service.AllRulesCache.AllRulesCacheAdapter

class FLYGeneratorPython extends AbstractGenerator {
	String name = null
	String env = null
	FunctionDefinition root = null
	var id_execution = null
	HashMap<String, HashMap<String, String>> typeSystem = null
	HashMap<String, FunctionDefinition> functionCalled = null
	String language
	int nthread
	int memory
	int timeout
	String user = null
	Resource resourceInput
	boolean isLocal
	boolean isAsync
	String env_name=""
	var list_environment = new ArrayList<String>(Arrays.asList("smp","aws","aws-debug","azure"));
	ArrayList listParams = null
	List<String> allReqs=null

	Map<String, String> graphMethodsReturnTypes = null

	def generatePython(Resource input, IFileSystemAccess2 fsa, IGeneratorContext context, String name_file,
		FunctionDefinition func, VariableDeclaration environment, HashMap<String, HashMap<String, String>> scoping,
		long id, boolean local, boolean async) {
		name = name_file
		root = func
		typeSystem = scoping
		id_execution = id
		env_name=environment.name
		if (!local) {
			env = (environment.right as DeclarationObject).features.get(0).value_s
			user = (environment.right as DeclarationObject).features.get(1).value_s
			language = (environment.right as DeclarationObject).features.get(5).value_s
			nthread = (environment.right as DeclarationObject).features.get(6).value_t
			memory = (environment.right as DeclarationObject).features.get(7).value_t
			timeout = (environment.right as DeclarationObject).features.get(8).value_t
		} else {
			env = "smp"
			language = (environment.right as DeclarationObject).features.get(2).value_s
			nthread = (environment.right as DeclarationObject).features.get(1).value_t
		}

		resourceInput = input
		functionCalled = new HashMap<String, FunctionDefinition>();
		for (element : input.allContents.toIterable.filter(FunctionDefinition)
			.filter[it.name != root.name]
			.filter[it.body.expressions.toList.filter(NativeExpression).length>0]) {

			functionCalled.put(element.name,element)
		}
		this.isAsync = async
		this.isLocal = local;
		doGenerate(input, fsa, context)
	}

	def setGraphMethodsReturnTypes(Map<String, String> map) {
		this.graphMethodsReturnTypes = map
	}

	override doGenerate(Resource input, IFileSystemAccess2 fsa, IGeneratorContext context) {
		allReqs = input.allContents
			.filter(RequireExpression)
			.filter[(it.environment.right as DeclarationObject).features.get(0).value_s != 'smp']
			.map[it.lib]
			.toList
		allReqs.add("pytz")
		allReqs.add("networkx")
		allReqs.add("fly_graph")
		if (env.equals("azure"))
			allReqs.add("azure-storage-queue")
		saveToRequirements(allReqs, fsa)
		println("Root name: " + root.name)
		if (isLocal) {
			fsa.generateFile(root.name + ".py", input.compilePython(root.name, true))
		}else {
			if(env.equals("aws-debug"))
				fsa.generateFile("docker-compose-script.sh",input.compileDockerCompose())
			fsa.generateFile(root.name +"_"+ env_name +"_deploy.sh", input.compileScriptDeploy(root.name, false))
			fsa.generateFile(root.name +"_"+ env_name + "_undeploy.sh", input.compileScriptUndeploy(root.name, false))
		}
	}

	def channelsNames(BlockExpression exps) {

		var names = new HashSet<String>();
		val chRecvs = resourceInput.allContents
				.filter[it instanceof ChannelReceive]
				.filter[functionContainer(it) === root.name]
				.filter[((it as ChannelReceive).target.environment.get(0).right as DeclarationObject).features.get(0).value_s.contains("aws")]
				.map[it as ChannelReceive]
				.map[it.target as VariableDeclaration]
				.map[it.name]

		val chSends = resourceInput.allContents
				.filter[it instanceof ChannelSend]
				.filter[functionContainer(it) === root.name]
				.filter[((it as ChannelSend).target.environment.get(0).right as DeclarationObject).features.get(0).value_s.contains("aws")]
				.map[it as ChannelSend]
				.map[it.target as VariableDeclaration]
				.map[it.name]

		while(chRecvs.hasNext()) {
			names.add(chRecvs.next())
		}
		while(chSends.hasNext()) {
			names.add(chSends.next())
		}

		return names.toArray()
	}

	def functionContainer(EObject e) {
		var parent = e.eContainer
		if (parent === null) {
			return ""
		} else if (parent instanceof FunctionDefinition) {
			return (parent as FunctionDefinition).name
		} else {
			return functionContainer(parent)
		}
	}

	def saveToRequirements(String[] requirements, IFileSystemAccess fsa) {
		var res = "";
		for (s: requirements) {
			res += s + "\n"
		}
		fsa.generateFile("requirements.txt", res)
	}

	def paramsName(List<Expression> expressions) {
			val tmp = new ArrayList()
			for(Expression e: expressions){
				tmp.add((e as VariableDeclaration).name)
				//println("sdasds "+ (e as VariableDeclaration).name)
			}


			return tmp
	}

	def generateBodyPyLocal(BlockExpression exps, List<Expression> parameters, String name, String env, boolean local) {
		val channelNames = channelsNames(exps)
		return '''
		import random
		import time
		import math
		import pandas as pd
		import json

		import socket
		import sys


		__sock_loc = socket.socket() # TODO
		__sock_loc.connect(('', 9090))

		«FOR chName : channelNames»
			«chName» = __sock_loc.makefile('rwb')
		«ENDFOR»

		«FOR fd:functionCalled.values()»
			«generatePyExpression(fd, name, local)»

		«ENDFOR»

		def main(event):
			«FOR exp : parameters»
				«IF typeSystem.get(name).get((exp as VariableDeclaration).name).equals("Table") »
					__columns=json.loads(event)[0].keys()
					«(exp as VariableDeclaration).name» = pd.read_json(event)
					«(exp as VariableDeclaration).name» = «(exp as VariableDeclaration).name»[__columns]
				«ELSE»
					«(exp as VariableDeclaration).name» = json.loads(event)
				«ENDIF»
			«ENDFOR»
			«FOR exp : exps.expressions»
				«generatePyExpression(exp,name, local)»
			«ENDFOR»
			__sock_loc.close()

		if __name__ == "__main__":

			__sock_data = socket.socket()
			__sock_data.connect(('', 9091))
			__sock_data_fh = __sock_data.makefile('rb')
			main(__sock_data_fh.readline())
		'''
	}

	def generateBodyPy(BlockExpression exps, List<Expression> parameters, String name, String env, boolean local) {
		//println("generaty python body "+name)
		//println(typeSystem.get(name))
		val channelNames = channelsNames(exps)
		listParams = paramsName(parameters)

		'''
			# python
			import os
			import random
			import time
			import math
			«IF allReqs.contains("pandas")»
			import pandas as pd
			import numpy as np
			«ENDIF»
			import json
			import urllib.request
			«IF allReqs.contains("networkx")»
			from fly.graph import Graph
			«ENDIF»

			«IF env.contains("aws")»
			import boto3
			«IF env.equals("aws")»
				sqs = boto3.resource('sqs')
			«ELSE»
				sqs = boto3.resource('sqs',endpoint_url='http://192.168.0.1:4576')
			«ENDIF»

			«FOR chName : channelNames»
				«chName» = sqs.get_queue_by_name(QueueName='«chName»-"${id}"')
			«ENDFOR»
			«ELSEIF env == "azure"»
			import azure.functions as func
			from azure.storage.queue import QueueService
			from azure.storage.queue.models import QueueMessageFormat
			«ENDIF»

			«IF env.contains("aws") »
			def handler(event,context):
				__environment = 'aws'
				id_func=event['id']
				data = event['data']
			«ELSEIF env == "azure"»
			def main(req: func.HttpRequest):
				__environment = 'azure'
				__queue_service = QueueService(account_name='"${storageName}"', account_key='"${storageKey}"')
				__queue_service.encode_function = QueueMessageFormat.text_base64encode
				__event = req.get_json()
				id_func= __event['id']
				data = __event['data']
			«ENDIF»
				«FOR exp : parameters»
					«IF typeSystem.get(name).get((exp as VariableDeclaration).name).equals("Table")» // || typeSystem.get(name).get((exp as VariableDeclaration).name).equals("File")»
						__columns = data[0].keys()
						«(exp as VariableDeclaration).name» = pd.read_json(json.dumps(data))
						«(exp as VariableDeclaration).name» = «(exp as VariableDeclaration).name»[__columns]
					«ELSEIF  typeSystem.get(name).get((exp as VariableDeclaration).name).contains("Matrix")»
						__«(exp as VariableDeclaration).name»_matrix = data[0]
						__«(exp as VariableDeclaration).name»_rows = data[0]['rows']
						__«(exp as VariableDeclaration).name»_cols = data[0]['cols']
						__«(exp as VariableDeclaration).name»_values = data[0]['values']
						__index = 0
						«(exp as VariableDeclaration).name» = [None] * (__«(exp as VariableDeclaration).name»_rows * __«(exp as VariableDeclaration).name»_cols)
						for __i in range(__«(exp as VariableDeclaration).name»_rows):
							for __j in range(__«(exp as VariableDeclaration).name»_cols):
								«(exp as VariableDeclaration).name»[__i*__«(exp as VariableDeclaration).name»_cols+__j] = __«(exp as VariableDeclaration).name»_values[__index]['value']
								__index+=1
					«ELSE»
				«(exp as VariableDeclaration).name» = data # TODO check
					«ENDIF»
				«ENDFOR»
				«FOR exp : exps.expressions»
					«generatePyExpression(exp,name, local)»
				«ENDFOR»
				«IF env.contains("aws") »
					__syncTermination = sqs.get_queue_by_name(QueueName='termination-"${function}"-"${id}"-'+str(id_func))
					__syncTermination.send_message(MessageBody=json.dumps('terminate'))
				«ELSEIF env == "azure"»
					__queue_service.put_message('termination-"${function}"-"${id}"-'+str(id_func), 'terminate')
				«ENDIF»
		'''
	}

	def generatePyExpression(Expression exp, String scope, boolean local) {

		var s = ''''''
		if (exp instanceof ChannelSend) {
			var env = (exp.target.environment.get(0).right as DeclarationObject).features.get(0).value_s ;//(exp.target as DeclarationObject).features.get(0).value_s;
			s += '''
			«IF local»
				«exp.target.name».write(json.dumps(«generatePyArithmeticExpression(exp.expression, scope, local)»).encode('utf8'))

			«ELSEIF (env.contains("aws"))»
«««				«println("exp.expression in " + env + ": " + exp.expression)»
				«IF exp.expression instanceof VariableLiteral»
«««					«println("exp.expression.variable.name: " + (exp.expression as VariableLiteral).variable.name)»
«««					«println("exp type: " + typeSystem.get(scope).get((exp.expression as VariableLiteral).variable.name))»
				«ENDIF»
				«IF exp.expression instanceof VariableLiteral && typeSystem.get(scope).get((exp.expression as VariableLiteral).variable.name).contains("Matrix") »
					«IF listParams.contains((exp.expression as VariableLiteral).variable.name)»
					__index=0
					for __i in range(__«(exp.expression as VariableLiteral).variable.name»_rows):
						for __j in range(__«(exp.expression as VariableLiteral).variable.name»_cols):
							__«(exp.expression as VariableLiteral).variable.name»_matrix['values'][__index]= «(exp.expression as VariableLiteral).variable.name»[__i*__«(exp.expression as VariableLiteral).variable.name»_cols+__j]
							__index+=1
					«ELSE»
						«println("I don't know what to do with " + (exp.expression as VariableLiteral).variable.name)»
					«ENDIF»
					«exp.target.name».send_message(
						MessageBody=json.dumps(__«(exp.expression as VariableLiteral).variable.name»_matrix)
					)
				«ELSE»
					«exp.target.name».send_message(
						MessageBody=json.dumps(«generatePyArithmeticExpression(exp.expression, scope, local)»)
					)
				«ENDIF»
			«ELSEIF env=="azure"»
			__queue_service.put_message('«exp.target.name»-"${id}"', json.dumps(«generatePyArithmeticExpression(exp.expression, scope, local)»))
			«ENDIF»

			'''
		} else if (exp instanceof VariableDeclaration) {
			if (exp.typeobject.equals("var") || exp.typeobject.equals("const")) {
				if (exp.right instanceof NameObjectDef) {  // it is a nameobjectdef
					typeSystem.get(scope).put(exp.name, "HashMap")
					s += '''«exp.name» = {'''
					var i = 0;
					for (f : (exp.right as NameObjectDef).features) {
						if (f.feature !== null) {
							typeSystem.get(scope).put(exp.name + "." + f.feature,
								valuateArithmeticExpression(f.value, scope, local))
							s = s + ''' '«f.feature»' : «generatePyArithmeticExpression(f.value, scope, local)»'''
						} else {
							typeSystem.get(scope).put(exp.name + "[" + i + "]",
								valuateArithmeticExpression(f.value, scope, local))
							s = s + ''' '«i»' :«generatePyArithmeticExpression(f.value, scope, local)»'''
							i++
						}
						if (f != (exp.right as NameObjectDef).features.last) {
							s += ''','''
						}
					}
					s += '''}'''

				} else if (exp.right instanceof ArrayDefinition) {
					val type = (exp.right as ArrayDefinition).type

					if((exp.right as ArrayDefinition).indexes.length==1){
						var len = (exp.right as ArrayDefinition).indexes.get(0).value
						typeSystem.get(scope).put(exp.name, "Array_"+type)
						s += '''
						«exp.name» = [None] * «generatePyArithmeticExpression(len, scope, local)»
						'''
					}else if((exp.right as ArrayDefinition).indexes.length==2){
						var row = (exp.right as ArrayDefinition).indexes.get(0).value
						var col = (exp.right as ArrayDefinition).indexes.get(1).value
						typeSystem.get(scope).put(exp.name, "Matrix_"+type+"_"+generatePyArithmeticExpression(col, scope, local))
						s += '''
						«exp.name» = [None] * («generatePyArithmeticExpression(row, scope, local)»* «generatePyArithmeticExpression(col, scope, local)»)
						'''
					}else if((exp.right as ArrayDefinition).indexes.length==3){
						var row = (exp.right as ArrayDefinition).indexes.get(0).value
						var col = (exp.right as ArrayDefinition).indexes.get(1).value
						var dep = (exp.right as ArrayDefinition).indexes.get(2).value
						typeSystem.get(scope).put(exp.name, "Matrix_"+type+"_"+generatePyArithmeticExpression(col, scope, local)+"_"+generatePyArithmeticExpression(dep, scope, local))
						s += '''
						«exp.name» = [None] * «generatePyArithmeticExpression(row, scope, local)» * «generatePyArithmeticExpression(col, scope, local)» *«generatePyArithmeticExpression(dep, scope, local)»
						'''
					}

				}
				else if(exp.right instanceof DeclarationObject){
					var type = (exp.right as DeclarationObject).features.get(0).value_s

					switch (type) {
						case "dataframe": {
							typeSystem.get(scope).put(exp.name, "Table")
							var path = "";
							if((exp.right as DeclarationObject).features.get(1).value_f!=null){
								path = (exp.right as DeclarationObject).features.get(1).value_f.name
							}else{
								path = (exp.right as DeclarationObject).features.get(1).value_s.replaceAll('"', '\'');
							}
							//var fileType = (exp.right as DeclarationObject).features.get(2).value_s
							var sep = (exp.right as DeclarationObject).features.get(2).value_s
							//path = path.replaceAll('"', '');
							var uri = '''«IF (exp as VariableDeclaration).onCloud && ! (path.contains("https://")) »«IF env == "aws"»https://s3.us-east-2.amazonaws.com«ELSEIF env=="aws-debug"»http://192.168.0.1:4572«ELSEIF env=="azure"»https://"${storageName}".blob.core.windows.net«ENDIF»/bucket-"${id}"/«path»«ELSE»«path»«ENDIF»'''

							s += '''
								«exp.name» = pd.read_csv('«uri»', sep='«sep»')
							'''
						}
						case "file":{
							typeSystem.get(scope).put(exp.name, "File")
							var path = "";
							if((exp.right as DeclarationObject).features.get(1).value_f!=null){
								path = (exp.right as DeclarationObject).features.get(1).value_f.name
							}else{
								path = (exp.right as DeclarationObject).features.get(1).value_s.replaceAll('"', '\'');
							}
							return '''
							if 'http' in «path»:
								«exp.name» = urllib.request.urlopen(urllib.request.Request(«path»,headers={'Content-Type':'application/x-www-form-urlencoded;charset=utf-8'}))
							else:
								«exp.name» = open(«path»,'rw')'''
						}
						case "graph": { // TODO check graph integration in Python (aws-debug)
							var path = ""
							if((exp.right as DeclarationObject).features.get(1).value_f != null){
								path = (exp.right as DeclarationObject).features.get(1).value_f.name
							}else{
								path = (exp.right as DeclarationObject).features.get(1).value_s.replaceAll('"', '\'');
							}
							var separator = (exp.right as DeclarationObject).features.get(2).value_s
							//var class = (exp.right as DeclarationObject).features.get(3).value_s // we can discard node class in Python
							//var numParams = (exp.environment.right as DeclarationObject).features.length
							var isDirected = (exp.right as DeclarationObject).features.get(4).value_s
							var isWeighted = (exp.right as DeclarationObject).features.get(5).value_s

							// set direction and weight properties of graph
							if (isDirected == "true")
							{
								isDirected = "True"
							}
							else
							{
								isDirected = "False"
							}

							if (isWeighted == "true")
							{
								isWeighted = "True"
							}
							else
							{
								isWeighted = "False"
							}

							typeSystem.get(scope).put(exp.name, "Graph")
							// TODO implement python logic to import a graph from file
							// 1st param: file path
							// 2nd param: separator character in CSV file
							// 3rd param: imported graph is directed
							// 4th param: imported graph is weighted
							return '''
								if 'http' in '«path»':
									graph_file = urllib.request.urlopen(urllib.request.Request('«path»',headers={'Content-Type':'application/x-www-form-urlencoded;charset=utf-8'}))
								else:
									graph_file = open('«path»','rw')
								«exp.name» = Graph.importGraph(graph_file, '«separator»', «isDirected», «isWeighted»)
							'''
						}
						default: {
							return ''''''
						}
					}
				} else {
					typeSystem.get(scope).put(exp.name, valuateArithmeticExpression(exp.right as ArithmeticExpression,scope,local))
					s += '''
						«exp.name» = «generatePyArithmeticExpression(exp.right as ArithmeticExpression, scope, local)»
					'''
				}
			}
		} else if (exp instanceof LocalFunctionCall) {
			val fc = (exp as LocalFunctionCall)
			val fd = (fc.target as FunctionDefinition)
			val inputs = (fc.input as LocalFunctionInput).inputs
			//functionCalled.put(fd.name, fd)
			s += '''«((exp as LocalFunctionCall).target).name»(«FOR par : inputs»«generatePyArithmeticExpression(par, scope, local)»«IF !par.equals(inputs.last)», «ENDIF»«ENDFOR»)'''
		} else if (exp instanceof FunctionDefinition) {
			val fd = (exp as FunctionDefinition)
			val name = fd.name
			val params = fd.parameters.map[it as VariableDeclaration].map[it.name]
			val body = fd.body as BlockExpression

			s += '''
				def «name»(«String.join(", ", params)»):
					«generatePyBlockExpression(body, scope, local)»
			'''
		} else if (exp instanceof IfExpression) {
			s += '''
				if «generatePyArithmeticExpression(exp.cond, scope, local)»:
					«generatePyExpression(exp.then,scope, local)»
				«IF exp.^else !== null»
					else:
						«generatePyExpression(exp.^else,scope, local)»
				«ENDIF»
			'''
		} else if (exp instanceof ForExpression) {
			s += '''
				«generatePyForExpression(exp,scope, local)»
			'''
		} else if (exp instanceof WhileExpression) {
			s += '''
				«generatePyWhileExpression(exp,scope, local)»
			'''
		} else if (exp instanceof BlockExpression) {
			s += '''
				«generatePyBlockExpression(exp,scope, local)»
			'''
		} else if (exp instanceof Assignment) {
			s += '''
				«generatePyAssignmentExpression(exp,scope,local)»
			'''
		} else if (exp instanceof PrintExpression) {
			s += '''
				print(«generatePyArithmeticExpression(exp.print, scope, local)»)
			'''
		} else if (exp instanceof SortExpression) {
			var isAscending = 'False'
			if (exp.type === 'asc') {
				isAscending = 'True'
			}
			s += '''
				«exp.target».sort_values(by=['«exp.taget»'], ascending=«isAscending»)
			'''
//		} else if (exp instanceof NativeExpression) {
//			s+='''
//				«generateJsNativeExpression(exp)»
//			'''
		} else if (exp instanceof FunctionReturn) {
			val fr = (exp as FunctionReturn)
			s += '''return «generatePyArithmeticExpression(fr.expression, scope, local)»'''
		} else if (exp instanceof PostfixOperation) {
			var postfixOp = ""
			switch(exp.feature) {
				case "++": postfixOp = "+=1"
				case "--": postfixOp = "-=1"
			}
			s +='''«generatePyArithmeticExpression(exp.variable, scope, local)»«postfixOp»'''

		} else if (exp instanceof NativeExpression){
			s +='''«generateNativeEpression(exp,scope,local)»'''
		} else if (exp instanceof VariableFunction) {
			s += '''«generatePyVariableFunction(exp,local,scope)»'''
		}

		return s
	}

	def generateNativeEpression(NativeExpression expression, String string, boolean b) {
		var code_lst = expression.code;
		var code_lst_split = code_lst.split("\n");
		var first_line = code_lst_split.get(1)
		var first_line_split = first_line.split("\t")
		var tabs= 0
		for(w : first_line_split){
			if (w.equals(""))
				tabs=tabs+1
		}
		var s=''''''
		var str = new StringBuilder();
		for(var  i=1;i<code_lst_split.size-1;i++){
			var line = code_lst_split.get(i)
			if(line.equals(""))
					str.append("")
				else
					str.append(line.substring(tabs))
				str.append("\n")
		}
		var ret_str = str.toString.replace("\"","'")
		return ret_str
	}

	def generatePyAssignmentExpression(Assignment assignment, String scope, boolean local) {
		if (assignment.feature !== null) {
			if (assignment.value instanceof CastExpression &&
				((assignment.value as CastExpression).target instanceof ChannelReceive)) {
				// If it is a CastExpression of a channel receive
				val channel = (((assignment.value as CastExpression).target as ChannelReceive).target) as VariableDeclaration
				if ((((assignment.value as CastExpression).target as ChannelReceive).target.environment.get(0).
					right as DeclarationObject).features.get(0).value_s.equals("aws")) { // aws environment2
					// And we are on AWS
					//TODO controllare receive_message
					if ((assignment.value as CastExpression).type.equals("Integer")) {
						// And we are trying to read an integer
						return '''
						«IF local»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» int(«channel.name».readline())
						«ELSE»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» int(«channel.name».receive_messages()[0])
						«ENDIF»
						'''
					} else if ((assignment.value as CastExpression).type.equals("Double")) {
						// And we are trying to read a double
						return '''
						«IF local»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» float(«channel.name».readline())
						«ELSE»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» float(«channel.name».receive_messages()[0])
						«ENDIF»
						'''
					}
				} else if ((((assignment.value as CastExpression).target as ChannelReceive).target.environment.get(0).
					right as DeclarationObject).features.get(0).value_s.equals("azure")) {
					// And we are on other environments
					if ((assignment.value as CastExpression).type.equals("Integer")) {
						return '''
						«IF local»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» int(«channel.name».readline())
						«ELSE»
						__msg =__queue_service.get_messages('«channel.name»-"${id}"')[0]
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» int(__msg.content)
						__queue_service.delete_message('«channel.name»-"${id}"',__msg.id, __msg.pop_receipt)
						«ENDIF»
						'''
					} else if ((assignment.value as CastExpression).type.equals("Double")) {
						return '''
						«IF local»
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» float(«channel.name».readline())
						«ELSE»
						__msg =__queue_service.get_messages('«channel.name»-"${id}"')[0]
						«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» float(__msg.content)
						__queue_service.delete_message('«channel.name»-"${id}"',__msg.id, __msg.pop_receipt)
						«ENDIF»
						'''
					}
				} else { // other environments
					return '''
					raise Exception('not now')
					'''
				}

			} else if (assignment.value instanceof ChannelReceive) {
				val channel = (((assignment.value as CastExpression).target as ChannelReceive).target) as VariableDeclaration
				// If it is an assignment of type Channel receive
				if (((assignment.value as ChannelReceive).target.environment.get(0).right as DeclarationObject).features.
					get(0).value_s.equals("aws")) {
					// And we are on AWS
					return '''
					«IF local»
					«channel.name».readline()
					«ELSE»
					«channel.name».receive_messages()[0]
					«ENDIF»
					'''
				} else if (((assignment.value as ChannelReceive).target.environment.get(0).right as DeclarationObject).features.
					get(0).value_s.equals("azure")) {
					return '''
					«IF local»
					«channel.name».readline()
					«ELSE»
					__msg =__queue_service.get_messages('«channel.name»-"${id}"')[0]
					«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» __msg.content
					__queue_service.delete_message('«channel.name»-"${id}"',__msg.id, __msg.pop_receipt)
					«ENDIF»
					'''
					}
				else { // other environments
					return '''
					raise Exception('not now')
					'''
				}
			} else {
				return '''
					«generatePyArithmeticExpression(assignment.feature, scope, local)» «assignment.op» «generatePyArithmeticExpression(assignment.value, scope, local)»
				'''
			}
		}

		if (assignment.feature_obj !== null) {
			if (assignment.feature_obj instanceof NameObject) {
				typeSystem.get(scope).put(
					((assignment.feature_obj as NameObject).name as VariableDeclaration).name + "." +
						(assignment.feature_obj as NameObject).value,
					valuateArithmeticExpression(assignment.value, scope, local))
				return '''
					«((assignment.feature_obj as NameObject).name as VariableDeclaration).name»['«(assignment.feature_obj as NameObject).value»'] = «generatePyArithmeticExpression(assignment.value, scope, local)»
				'''
			}
			if (assignment.feature_obj instanceof IndexObject) {
				if (typeSystem.get(scope).get((assignment.feature_obj as IndexObject).name.name).contains("Array")) {
					return '''
					«(assignment.feature_obj as IndexObject).name.name»[«generatePyArithmeticExpression((assignment.feature_obj as IndexObject).indexes.get(0).value, scope, local)»] = «generatePyArithmeticExpression((assignment.value), scope, local)»
					'''
				} else if (typeSystem.get(scope).get((assignment.feature_obj as IndexObject).name.name).contains("Matrix")) {
					if ((assignment.feature_obj as IndexObject).indexes.length == 2) {
						var i = generatePyArithmeticExpression((assignment.feature_obj as IndexObject).indexes.get(0).value ,scope, local);
						var j = generatePyArithmeticExpression((assignment.feature_obj as IndexObject).indexes.get(1).value ,scope, local);

						//var col = typeSystem.get(scope).get((assignment.feature_obj as IndexObject).name.name).split("_").get(2)

						return '''
							«(assignment.feature_obj as IndexObject).name.name»[«i»*__«(assignment.feature_obj as IndexObject).name.name»_cols+«j»] = «generatePyArithmeticExpression(assignment.value, scope, local)»
						'''
					}
				} else {
					return '''
					«(assignment.feature_obj as IndexObject).name.name»[«generatePyArithmeticExpression((assignment.feature_obj as IndexObject).indexes.get(0).value, scope, local)»] = «generatePyArithmeticExpression(assignment.value, scope, local)»
					'''
				}
			}
		}
	}

	def generatePyWhileExpression(WhileExpression exp, String scope, boolean local) {
		'''
			while «generatePyArithmeticExpression(exp.cond, scope, local)»:
				«generatePyExpression(exp.body,scope, local)»
		'''
	}

	def generatePyForExpression(ForExpression exp, String scope, boolean local) {
		if(exp.index.indices.length == 1){
			if (exp.object instanceof CastExpression) {
				if ((exp.object as CastExpression).type.equals("Dat")) {
					return '''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in «(exp.object as VariableLiteral).variable.name».itertuples(index=False):
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				} else if ((exp.object as CastExpression).type.equals("Object")) {
					val variableName = (exp.index.indices.get(0) as VariableDeclaration).name
					return '''
						for «variableName»k, «variableName»v in «((exp.object as CastExpression).target as VariableLiteral).variable.name».items():
							«(exp.index.indices.get(0) as VariableDeclaration).name» = {'k': «variableName»k, 'v': «variableName»v}
							«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				}
			} else if (exp.object instanceof RangeLiteral) {
				val lRange = (exp.object as RangeLiteral).value1
				val rRange = (exp.object as RangeLiteral).value2
				return '''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in range(«lRange», «rRange»):
						«generatePyForBodyExpression(exp.body, scope, local)»
				'''
			} else if (exp.object instanceof VariableLiteral) {
//				println("Variable: "+ (exp.object as VariableLiteral).variable.name + " type: " + typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name))
				if (typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name) === null) {
					println("[Py] BEWARE! Variable " + (exp.object as VariableLiteral).variable.name + " type is null!")
					return ''''''
				} else if ((((exp.object as VariableLiteral).variable.typeobject.equals('var') &&
					((exp.object as VariableLiteral).variable.right instanceof NameObjectDef) ) ||
					typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).equals("HashMap"))) {
					val variableName = (exp.index.indices.get(0) as VariableDeclaration).name
					return '''
						for «variableName»k, «variableName»v in «(exp.object as VariableLiteral).variable.name».items():
							«(exp.index.indices.get(0) as VariableDeclaration).name» = {'k': «variableName»k, 'v': «variableName»v}
							«generatePyForBodyExpression(exp.body, scope, local)»

					'''
				} else if ((exp.object as VariableLiteral).variable.typeobject.equals('dat') ||
					typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).equals("Table")
					) {
					return '''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in «(exp.object as VariableLiteral).variable.name».itertuples(index=False):
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				} else if(typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).equals("File") ){
					return'''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in «(exp.object as VariableLiteral).variable.name»:
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				}else if (typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).equals("Directory") ){
					return '''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in os.listdir(«(exp.object as VariableLiteral).variable.name»):
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				} else if (typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).contains("[]") ){
					return'''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in «(exp.object as VariableLiteral).variable.name»:
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				}
			} else if (exp.object instanceof VariableFunction) {
				// TODO replicate 'for' structure for variable function
				var function = exp.object as VariableFunction
				if (typeSystem.get(scope).get(function.target.name).contains("Graph")) {
//					println("GRAPH TEST (varDec, i.e. exp.index.indices.get(0)): " + varDec)
//					println("GRAPH TEST (function, i.e. exp.object): " + function)
//					println("GRAPH TEST (exp.body): " + exp.body)
					return '''
					for «(exp.index.indices.get(0) as VariableDeclaration).name» in «generatePyVariableFunction(function, local, scope)»:
						«generatePyForBodyExpression(exp.body, scope, local)»
					'''
				} else {
					println("Looping over " + function)
				}
			}
		}else if(exp.index.indices.length == 2){
			if(typeSystem.get(scope).get((exp.object as VariableLiteral).variable.name).contains("Matrix")){
				var row = (exp.index.indices.get(0) as VariableDeclaration).name
				var col = (exp.index.indices.get(1) as VariableDeclaration).name
				return '''
				for «row» in range(__«(exp.object as VariableLiteral).variable.name»_rows):
					for «col» in range(__«(exp.object as VariableLiteral).variable.name»_cols):
						«generatePyForBodyExpression(exp.body, scope, local)»
				'''
			}
		}

	}

	// TODO test
	def generatePyForBodyExpression(Expression body, String scope, boolean local) {
		if (body instanceof BlockExpression) {
			generatePyBlockExpression(body, scope, local)
		} else {
			generatePyExpression(body, scope, local)
		}
	}

	def generatePyBlockExpression(BlockExpression block, String scope, boolean local) {
		'''
		«FOR exp : block.expressions»
«««			«println("expression in block: " + exp)»
			«generatePyExpression(exp,scope, local)»
		«ENDFOR»
		'''
	}

	def generatePyArithmeticExpression(ArithmeticExpression exp, String scope, boolean local) {
		if (exp instanceof BinaryOperation) {
			if (exp.feature.equals("and"))
				return '''«generatePyArithmeticExpression(exp.left, scope, local)» and «generatePyArithmeticExpression(exp.right, scope, local)»'''
			else if (exp.feature.equals("or"))
				return '''«generatePyArithmeticExpression(exp.left, scope, local)» or «generatePyArithmeticExpression(exp.right, scope, local)»'''
			else if (exp.feature.equals("+")) {
//				println("Exp left: " + exp.left + ", Exp right: " + exp.right)
//				println("Exp left type: " + valuateArithmeticExpression(exp.left, scope, local))
//				println("Exp right type: " + valuateArithmeticExpression(exp.right, scope, local))
//				println("type system: " + typeSystem)
				val leftTypeString = valuateArithmeticExpression(exp.left, scope, local).equals("String");
				val rightTypeString = valuateArithmeticExpression(exp.right, scope, local).equals("String");
				if ((leftTypeString && rightTypeString) || (!leftTypeString && !rightTypeString)) {
					return '''«generatePyArithmeticExpression(exp.left, scope, local)» «exp.feature» «generatePyArithmeticExpression(exp.right, scope, local)»'''
				} else if (leftTypeString) {
					return '''«generatePyArithmeticExpression(exp.left, scope, local)» «exp.feature» str(«generatePyArithmeticExpression(exp.right, scope, local)»)'''
				} else {
					return '''str(«generatePyArithmeticExpression(exp.left, scope, local)») «exp.feature» «generatePyArithmeticExpression(exp.right, scope, local)»'''
				}
			} else
				return '''«generatePyArithmeticExpression(exp.left, scope, local)» «exp.feature» «generatePyArithmeticExpression(exp.right, scope, local)»'''
		} else if (exp instanceof UnaryOperation) {
			return '''«exp.feature» «generatePyArithmeticExpression(exp.operand, scope, local)» '''
		} else if (exp instanceof PostfixOperation) {
			var postfixOp = ""
			switch(exp.feature) { // TODO mai?
				case "++": postfixOp = "+=1"
				case "--": postfixOp = "-=1"
			}
			return '''«generatePyArithmeticExpression(exp.variable, scope, local)»«postfixOp»'''
		} else if (exp instanceof ParenthesizedExpression) {
			return '''(«generatePyArithmeticExpression(exp.expression, scope, local)»)'''
		} else if (exp instanceof NumberLiteral) {
			return '''«exp.value»'''
		} else if (exp instanceof BooleanLiteral) {
			return '''«exp.value.toFirstUpper»'''
		} else if (exp instanceof FloatLiteral) {
			return '''«exp.value»'''
		} else if(exp instanceof EnvironemtLiteral){
			return '''__environment'''
		}
		if (exp instanceof StringLiteral) {
			val quote = "'"
			return '''«quote»«exp.value»«quote»'''
		} else if (exp instanceof VariableLiteral) {
			return '''«exp.variable.name»'''
		} else if (exp instanceof VariableFunction) {
			return generatePyVariableFunction(exp, local, scope)
		} else if (exp instanceof TimeFunction) {
			if (exp.value !== null) {
				return '''int(time.time() * 1000) - «exp.value.name»'''
			} else {
				return '''int(time.time() * 1000)'''
			}
		} else if (exp instanceof NameObject) {
			if ((exp.name.right instanceof DeclarationObject) && list_environment.contains((exp.name.right as DeclarationObject).features.get(0).value_s)){
				return '''__environment'''
			}else{
				return '''«(exp.name as VariableDeclaration).name»['«exp.value»']'''
			}
		} else if (exp instanceof IndexObject) { //array
			if (exp.indexes.length == 1) {
				return '''«(exp.name as VariableDeclaration).name»[«generatePyArithmeticExpression(exp.indexes.get(0).value, scope, local)»]'''
			} else if(exp.indexes.length == 2) { //matrix 2d
//				println("Expression indexes: " + exp.indexes)
//				println("Expression: " + exp)
				var i = generatePyArithmeticExpression(exp.indexes.get(0).value ,scope, local);
				var j = generatePyArithmeticExpression(exp.indexes.get(1).value ,scope, local);

				var col = typeSystem.get(scope).get((exp.name as VariableDeclaration).name).split("_").get(2)
				return '''
					«(exp.name as VariableDeclaration).name»[(«i»*__«(exp.name as VariableDeclaration).name»_cols)+«j»]['value']
				'''
			} else { // matrix 3d
				
			}
		} else if (exp instanceof CastExpression) {
			return '''«generatePyCast(exp, scope, local)»'''
		} else if (exp instanceof MathFunction) {
			// TODO mapping
			if (exp.feature.equals('abs')) {
				return '''abs(«FOR par : exp.expressions»«generatePyArithmeticExpression(par, scope, local)»«IF !par.equals(exp.expressions.last)», «ENDIF»«ENDFOR»)'''
			}
			return '''math.«exp.feature»(«FOR par : exp.expressions»«generatePyArithmeticExpression(par, scope, local)»«IF !par.equals(exp.expressions.last)», «ENDIF»«ENDFOR»)'''
		} else if (exp instanceof ChannelReceive) {
			val channelName = (((exp as ChannelReceive).target) as VariableDeclaration).name
			if (local) {
				return '''«channelName».readline()'''
			}
			var env = ((exp.target.environment as VariableDeclaration).right as DeclarationObject).features.get(0).value_s
			if(env.equals("aws")){ //TODO cancellare messaggio, controllare se non viene mai invocata
				return '''«channelName».receive_messages()[0]'''
			}else if(env.equals("azure")){
				return '''__queue_service.receive_messages('«channelName»-"${id}"')[0]'''
			}else{
				return'''
				'''
			}
		} else if (exp instanceof LocalFunctionCall) {
			return generatePyExpression(exp as LocalFunctionCall, scope, local)
		} else {
			return '''# ???'''
		}
	}

	def generatePyVariableFunction(VariableFunction exp, Boolean local, String scope) {
		// TODO define
//		println("[Py] handling " + exp.target.name + " of type " + (exp.target.right as DeclarationObject).features.get(0).value_s)
		if ((exp.target.right instanceof DeclarationObject) && (exp.target.right as DeclarationObject).features.get(0).value_s.equals("random") ) {
			return '''random.random()'''
		} else if(exp.feature.equals("length")){
			return '''len(«exp.target.name»)'''
		} else if(exp.feature.equals("containsKey")){
			return '''«generatePyArithmeticExpression(exp.expressions.get(0),scope,local)» in «exp.target.name»'''
		} else if(exp.feature.equals("split")){
			return '''str(«exp.target.name»).split(«generatePyArithmeticExpression(exp.expressions.get(0),scope,local)»)'''
		} else if ((exp.target.right instanceof DeclarationObject) && (exp.target.right as DeclarationObject).features.get(0).value_s.equals("graph")) {
			// begin graph methods declaration
			var args = exp.expressions.size;
			var invocation = '''«exp.target.name».«exp.feature»'''
//			println("[Py] Building " + invocation)
			if (args == 1) {
				return '''«invocation»(«generatePyArithmeticExpression(exp.expressions.get(0),scope,local)»)'''
			} else if (args > 1) {
				// please leave this return indentation like this
				return '''«invocation»(«
					FOR i : 0 ..< args - 1»«
						generatePyArithmeticExpression(
							exp.expressions.get(i),
							scope,
							local
						)», «
					ENDFOR»«
					generatePyArithmeticExpression(
						exp.expressions.get(args - 1),
						scope,
						local
					)
				»)'''
			} else {
				return '''«invocation»()'''
			}
		}
	}

	def generatePyCast(CastExpression cast, String scope, boolean local) {
		switch(cast.type) { // 'String' | 'Integer' | 'Date' | 'Dat' | 'Object'  | 'Double'
			case "String": return '''str(«generatePyArithmeticExpression(cast.target, scope, local)»)'''
			case "Integer": return '''int(«generatePyArithmeticExpression(cast.target, scope, local)»)'''
			case "Dat": return '''pd.read_json(«generatePyArithmeticExpression(cast.target, scope, local)»)'''
			case "Object": return '''«generatePyArithmeticExpression(cast.target, scope, local)»'''
			case "Double": return '''float(«generatePyArithmeticExpression(cast.target, scope, local)»)'''
		}
	}

	def String valuateArithmeticExpression(ArithmeticExpression exp, String scope, boolean local) {
		if (exp instanceof NumberLiteral) {
			return "Integer"
		} else if (exp instanceof BooleanLiteral) {
			return "Boolean"
		} else if (exp instanceof StringLiteral) {
			return "String"
		} else if (exp instanceof FloatLiteral) {
			return "Double"
		} else if (exp instanceof VariableLiteral) { // TODO  fix with the current grammar
			val variable = exp.variable
			if (variable.typeobject === null) {
				println("[Py] BEWARE! Variable " + exp.variable.name + " type is null!")
			} else if (variable.typeobject.equals("dat")) {
				return "Table"
			} else if (variable.typeobject.equals("channel")) {
				return "Channel"
			} else if (variable.typeobject.equals("var")) {
				if (variable.right instanceof NameObjectDef) {
					return "HashMap"
				} else if (variable.right instanceof ArithmeticExpression) {
					return valuateArithmeticExpression(variable.right as ArithmeticExpression, scope, local)
				} else {
					return typeSystem.get(scope).get(variable.name) // if it's a parameter of a FunctionDefinition
				}
			}
			return "variable"
		} else if (exp instanceof NameObject) {
			return typeSystem.get(scope).get(exp.name.name + "." + exp.value)
		} else if (exp instanceof IndexObject) {
//			println(scope + " type system " + typeSystem.get(scope))
//			println("Expression name name: " + exp.name.name)
			if (typeSystem.get(scope).get(exp.name.name).contains("Array") || typeSystem.get(scope).get(exp.name.name).contains("Matrix") ) {
				return typeSystem.get(scope).get(exp.name.name).split("_").get(1);
			} else {
				return typeSystem.get(scope).get(exp.name.name + "[" + generatePyArithmeticExpression(exp.indexes.get(0).value, scope, local) + "]");
			}
		} else if (exp instanceof DatTableObject) {
			return "Table"
		}
		if (exp instanceof UnaryOperation) {
			if (exp.feature.equals("!"))
				return "Boolean"
			return valuateArithmeticExpression(exp.operand, scope, local)
		}
		if (exp instanceof BinaryOperation) {
			var left = valuateArithmeticExpression(exp.left, scope, local)
			var right = valuateArithmeticExpression(exp.right, scope, local)
			if (exp.feature.equals("+") || exp.feature.equals("-") || exp.feature.equals("*") ||
				exp.feature.equals("/")) {
				if (left.equals("String") || right.equals("String"))
					return "String"
				else if (left.equals("Double") || right.equals("Double"))
					return "Double"
				else
					return "Integer"
			} else
				return "Boolean"
		} else if (exp instanceof PostfixOperation) {
			return valuateArithmeticExpression((exp as PostfixOperation).variable, scope, local)
		} else if (exp instanceof CastExpression) {
			if (exp.type.equals("Object")) {
				return "HashMap"
			}
			if (exp.type.equals("String")) {
				return "String"
			}
			if (exp.type.equals("Integer")) {
				return "Integer"
			}
			if (exp.type.equals("Float")) {
				return "Double"
			}
			if (exp.type.equals("Dat")) {
				return "Table"
			}
			if (exp.type.equals("Date")) {
				return "LocalDate"
			}
		} else if (exp instanceof ParenthesizedExpression) {
			return valuateArithmeticExpression(exp.expression, scope, local)
		}
		if (exp instanceof MathFunction) {
			if (exp.feature.equals("round")) {
				return "Integer"
			} else {
				for (el : exp.expressions) {
					if (valuateArithmeticExpression(el, scope, local).equals("Double")) {
						return "Double"
					}
				}
				return "Integer"
			}
		} else if (exp instanceof TimeFunction) {
			return "Long"
		} else if (exp instanceof VariableFunction) {
//			println("Expression: " + exp)
//			println("Expression target: " + exp.target)
			if (exp.target.typeobject.equals("var")) {
				if (exp.feature.equals("split")) {
					return "String[]"
				} else if (exp.feature.contains("indexOf") || exp.feature.equals("length")) {
					return "Integer"
				} else if (exp.feature.equals("concat") || exp.feature.equals("substring") ||
					exp.feature.equals("toLowerCase") || exp.feature.equals("toUpperCase")) {
					return "String"
				} else {
					return "Boolean"
				}
			} else if (exp.target.typeobject.equals("random")) {
				if (exp.feature.equals("nextBoolean")) {
					return "Boolean"
				} else if (exp.feature.equals("nextDouble")) {
					return "Double"
				} else if (exp.feature.equals("nextInt")) {
					return "Integer"
				}
			} else if (exp.target.typeobject.equals("graph")) { // TODO check graph method types
				return this.graphMethodsReturnTypes.getOrDefault(exp.feature, "Object")
			}
		} else {
			return "Object"
		}
	}

	def CharSequence compilePython(Resource resource, String name, boolean local) '''
		«generateBodyPyLocal(root.body,root.parameters,name,env, local)»
	'''

	def CharSequence compileScriptDeploy(Resource resource, String name, boolean local){
		switch this.env {
		   case "aws": AWSDeploy(resource,name,local,false)
		   case "aws-debug": AWSDebugDeploy(resource,name,local,true)
		   case "azure": AzureDeploy(resource,name,local)
		   default: this.env+" not supported"
		}
	}

	def CharSequence AWSDeploy(Resource resource, String name, boolean local, boolean debug)
	'''
	«val profile = if (debug) "dummy_fly_debug" else "${user}"»
	«val endpoint = "http://localhost"»
	#!/bin/bash

	if [[ $# -eq 0 ]]; then
	    echo "No arguments supplied. ./aws_deploy.sh <user_profile> <function_name> <id_function_execution>"
	    exit 1
	fi

	echo "Checking whether aws-cli is installed"
	which aws
	if [[ $? -eq 0 ]]; then
	    echo "aws-cli is installed, continuing..."
	else
	    echo "You need aws-cli to deploy this lambda. Google 'aws-cli install'"
	    exit 1
	fi

	# check installed Python version
««« TODO this may work for localstack versions more recent than 0.9.6
	#PYVER="$(python3 -V | grep -Po "(\d+\.\d+)" | head -1)"
	#echo "Python version: $PYVER"
	#PYVER_C=${PYVER/./}
	#if (( $PYVER_C != 27 )) && (( $PYVER_C < 36 || $PYVER_C > 38 )); then
	#    echo "You need to install Python 2.7, 3.6, 3.7 or 3.8 on your local machine"
	#    exit 1
	#fi

	echo "Checking whether virtualenv is installed"
	which virtualenv
	if [[ $? -eq 0 ]]; then
	    echo "virtualenv is installed, continuing..."
	else
	    echo "You need to install virtualenv. Google 'virtualenv install'"
	    exit 1
	fi

	«IF debug»
	aws configure list --profile «profile»
	if [[ $? -eq 0 ]]; then
	    echo "dummy user found, continuing..."
	else
	    echo "creating dummy user..."
	    aws configure set aws_access_key_id dummy --profile «profile»
	    aws configure set aws_secret_access_key dummy --profile «profile»
	    aws configure set region us-east-1 --profile «profile»
	    aws configure set output json --profile «profile»
	    echo "dummy user created"
	fi
	«ENDIF»

	user=$1
	function=$2
	id=$3

	echo '{
	    "Version": "2012-10-17",
	    "Statement": [
	        {
	            "Effect": "Allow",
	            "Action": [
	                "sqs:DeleteMessage",
	                "sqs:GetQueueAttributes",
	                "sqs:ReceiveMessage",
	                "sqs:SendMessage",
	                "sqs:*"
	            ],
	            "Resource": "*"
	        },
	        {
	            "Effect": "Allow",
	            "Action": [
	                "s3:*"
	            ],
	            "Resource": "*"
	        },
	        {
	            "Effect":"Allow",
	            "Action": [
	                "logs:CreateLogGroup",
	                "logs:CreateLogStream",
	                "logs:PutLogEvents"
	            ],
	            "Resource": "*"
	        }
	    ]
	}' > policyDocument.json

	echo '{
	    "Version": "2012-10-17",
	    "Statement": [
	        {
	            "Effect": "Allow",
	            "Principal": {
	                "Service": "lambda.amazonaws.com"
	            },
	            "Action": "sts:AssumeRole"
	        }
	    ]
	}' > rolePolicyDocument.json

	# create role policy
	echo "creation of role lambda-sqs-execution ..."

	role_arn=$(aws iam get-role --role-name lambda-sqs-execution --query 'Role.Arn' --profile «profile»«IF debug» --endpoint-url=«endpoint»:4593«ENDIF»)

	if [[ -z $role_arn ]]; then
	    role_arn=$(aws iam create-role --role-name lambda-sqs-execution --assume-role-policy-document file://rolePolicyDocument.json --output json --query 'Role.Arn' --profile «profile»«IF debug» --endpoint-url=«endpoint»:4593«ENDIF»)
	fi

	echo "role lambda-sqs-execution created at ARN "$role_arn

	aws iam put-role-policy --role-name lambda-sqs-execution --policy-name lambda-sqs-policy --policy-document file://policyDocument.json --profile «profile»«IF debug» --endpoint-url=http://localhost:4593«ENDIF»
	aws logs create-log-group --log-group-name «IF debug»dummy_«ENDIF»fly_logs --profile «profile»«IF debug» --endpoint-url=«endpoint»:4586«ENDIF»
	aws logs create-log-stream --log-group-name «IF debug»dummy_«ENDIF»fly_logs --log-stream-name dummy_fly_log_stream --profile «profile»«IF debug» --endpoint-url=«endpoint»:4586«ENDIF»


	echo "Installing requirements"

	# create and enter virtual environment
	virtualenv venv -p «language»
	source venv/bin/activate


	echo "Checking wheter PIP is installed"
	which pip3
	if [[ $? -eq 0 ]]; then
	    echo "PIP is installed"
	else
	    echo "You need to install PIP. Google 'pip install'"
	    exit 1
	fi

	#PIPVER="$(python3 -m pip -V | grep -Po "(\d+\.)+\d+" | grep -Po "\d+" | head -1)"
	#if [[ ${PIPVER} -lt 19 ]]; then
	#    echo "pip version is too old. installing new one"
««« PIP would be out of date anyway
	echo "Updating PIP..."
	    python3 -m pip install --upgrade pip
	#fi

	python3 -m pip install -r ./src-gen/requirements.txt

	echo
	echo "add precompiled libraries"
	cd venv/lib/«language»/site-packages/
	«IF allReqs.contains("ortools")»

	echo "installing ortools"
	rm -rf ortools*
	wget -q https://files.pythonhosted.org/packages/64/13/8c8d0fe23da0767ec0f8d00ad14619a20bc6d55ca49a3bd13700e629a1be/ortools-6.10.6025-cp36-cp36m-manylinux1\_x86\_64.whl
	unzip -q ortools-6.10.6025-cp36-cp36m-manylinux1\_x86\_64.whl
	rm ortools-6.10.6025-cp36-cp36m-manylinux1\_x86\_64.whl
	echo "ortools installed"
	«ENDIF»
	«IF allReqs.contains("pandas")»

	echo "installing pandas"
	rm -rf pandas*
	wget -q https://files.pythonhosted.org/packages/f9/e1/4a63ed31e1b1362d40ce845a5735c717a959bda992669468dae3420af2cd/pandas-0.24.0-cp36-cp36m-manylinux1\_x86\_64.whl
	unzip -q pandas-0.24.0-cp36-cp36m-manylinux1\_x86\_64.whl
	rm pandas-0.24.0-cp36-cp36m-manylinux1\_x86\_64.whl
	echo "pandas installed"
	«ENDIF»
	«IF allReqs.contains("numpy")»

	echo "installing numpy"
	rm -rf numpy*
	wget -q https://files.pythonhosted.org/packages/7b/74/54c5f9bb9bd4dae27a61ec1b39076a39d359b3fb7ba15da79ef23858a9d8/numpy-1.16.0-cp36-cp36m-manylinux1\_x86\_64.whl
	unzip -q numpy-1.16.0-cp36-cp36m-manylinux1\_x86\_64.whl
	rm numpy-1.16.0-cp36-cp36m-manylinux1\_x86\_64.whl
	echo "numpy installed"
	«ENDIF»
	«IF allReqs.contains("networkx")»

	echo "installing networkx"
	rm -rf networkx*
	wget -q https://files.pythonhosted.org/packages/41/8f/dd6a8e85946def36e4f2c69c84219af0fa5e832b018c970e92f2ad337e45/networkx-2.4-py3-none-any.whl -O networkx.whl
	unzip -q networkx.whl
	rm networkx.whl
	rm -rf decorator*
	wget -q https://files.pythonhosted.org/packages/ed/1b/72a1821152d07cf1d8b6fce298aeb06a7eb90f4d6d41acec9861e7cc6df0/decorator-4.4.2-py2.py3-none-any.whl -O decorator.whl
	unzip -q decorator.whl
	rm decorator.whl
	echo "networkx installed"
	«ENDIF»
	«IF allReqs.contains("fly_graph")»

	echo "installing FLY graph"
	rm -rf fly*
	wget -q https://github.com/bissim/FLY-graph/releases/download/0.0.1-dev%2B20200706/fly_graph-0.0.1.dev0+20200706-py3-none-any.whl -O fly_graph.whl
	unzip -q -d . fly_graph.whl fly/*
	rm fly_graph.whl
	echo "FLY graph installed"
	«ENDIF»

	echo
	echo "creating zip package"
	zip -q -r9 ../../../../${id}\_lambda.zip .
	echo "zip created"

	cd ../../../../


	# generate Python function script
	echo "«generateBodyPy(root.body, root.parameters, name, env, local)»

	«FOR fd:functionCalled.values()»

	«generatePyExpression(fd, name, local)»

	«ENDFOR»
	" > ${function}.py


	zip -qg ${id}_lambda.zip ${function}.py

	# exit from virtual environment
	deactivate


	# create lambda function
	echo "creation of the lambda function"

	echo "zip file too big, uploading it using s3"
	echo "creating bucket for s3"
	aws s3 mb s3://${function}${id}bucket --profile «profile»«IF debug» --endpoint-url=«endpoint»:4572«ENDIF»
	echo "s3 bucket created. uploading file"
	aws s3 cp ${id}_lambda.zip s3://${function}${id}bucket --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers --profile «profile»«IF debug» --endpoint-url=«endpoint»:4572«ENDIF»
	echo "file uploaded, creating function"
	aws lambda create-function --function-name ${function}_${id} --code S3Bucket=""${function}""${id}"bucket",S3Key=""${id}"_lambda.zip" --handler ${function}.handler --runtime «language» --role ${role_arn//\"} --memory-size «memory» --timeout «timeout» --profile «profile»«IF debug» --endpoint-url=«endpoint»:4574«ENDIF»
	echo "lambda function created"


	# clear
	rm -r venv/
	rm ${function}.py
	rm ${id}_lambda.zip
	rm rolePolicyDocument.json
	rm policyDocument.json
	'''

	def CharSequence AWSDebugDeploy(Resource resource, String name, boolean local, boolean debug)
	'''«AWSDeploy(resource, name, local, debug)»'''

	def CharSequence compileDockerCompose(Resource resource)'''
	docker network create -d bridge --subnet 192.168.0.0/24 --gateway 192.168.0.1 mynet
	echo \
	"version: '3.7'

	services:
	  localstack:
	    image: localstack/localstack:0.9.6
	    ports:
	      - '4563-4599:4563-4599'
	      - '\${PORT_WEB_UI-8080}:\${PORT_WEB_UI-8080}'
	    environment:
	      - SERVICES=\${SERVICES- s3, sqs, lambda, iam, cloudwatch, logs}
	      - DEBUG=\${DEBUG- 1}
	      - DATA_DIR=\${DATA_DIR- }
	      - PORT_WEB_UI=\${PORT_WEB_UI- }
	      - LAMBDA_EXECUTOR=\${LAMBDA_EXECUTOR- docker}
	      - KINESIS_ERROR_PROBABILITY=\${KINESIS_ERROR_PROBABILITY- }
	      - DOCKER_HOST=unix:///var/run/docker.sock
	      - HOSTNAME=192.168.0.1
	      - HOSTNAME_EXTERNAL=192.168.0.1
	      - LOCALSTACK_HOSTNAME=192.168.0.1
	    volumes:
	      - '/var/run/docker.sock:/var/run/docker.sock'
	    tmpfs:
	      - /tmp/aws_debug
	" > docker-compose.yml

	docker-compose up
	'''

	def CharSequence AzureDeploy(Resource resource, String name, boolean local)
	'''
		#!/bin/bash

«««		#Check if script is running as sudo
«««		if [[ $# -ne 6 ]]; then
«««			echo "Error in number of parameters, run with:"
«««			echo "<app-name> <function-name> <executionId> <clientId> <tenantId> <secret> <subscriptionId> <timeout> <storageName> <storageKey>"
«««			exit 1
«««		fi


		if [ $# -ne 9 ]
		  then
		    echo "No arguments supplied. ./azure_deploy.sh <app-name> <function-name> <executionId> <clientId> <tenantId> <secret> <subscriptionId>  <storageName> <storageKey>"
		    exit 1
		fi

		app=$1
		function=$2
		id=$3
		user=$4
		tenant=$5
		secret=$6
		subscription=$7
		storageName=$8
		storageKey=$9

		az login --service-principal -u ${user} -t ${tenant} -p ${secret}

		#Check if python is installed
		if !(command -v python3 &>/dev/null) then
			echo "Script require python 3.6"
			exit 1;
		fi

		#Check if Azure Functions Core Tools is installed
		if !(command -v az &>/dev/null) then
			echo "Script require Azure Functions Core Tools"
			exit 1;
		fi

		#Virtual environment
		echo "Creating the virtual environment"

		if [ ! -d .env ]; then

			python3.6 -m venv .env
		fi

		source .env/bin/activate
		echo "Virtual environment has been created"

		#Local function's local project
		echo "Creating function's local project"

		if [ ! -d ${app}${id} ]; then
			func init ${app}${id} --worker-runtime=python --no-source-control -n

			cp ./src-gen/requirements.txt ./${app}${id}

			cd ${app}${id}


			rm -f host.json
			echo '{
				"version": "2.0",
				"functionTimeout": "«String.format("%02d:%02d:%02d",0,timeout/60,timeout%60)»"
			}' > host.json;
		else
			cd ${app}${id}
		fi

		echo "Function's local project has been created"

		mkdir ${function}
		cd ${function}

		echo "Creating Function's files..."

		echo '{
		  "scriptFile": "function.py",
		  "bindings": [
		    {
		      "authLevel": "system",
		      "type": "httpTrigger",
		      "direction": "in",
		      "name": "req",
		      "methods": [
		        "post"
		      ]
		    }
		  ]
		}' > function.json
		echo "Function.json created"

		#Creating function's source file
		echo "«generateBodyPy(root.body,root.parameters,name,env, local)»

			«FOR fd:functionCalled.values()»

			«generatePyExpression(fd, name, local)»

			«ENDFOR»
			" > function.py
		echo "Function.py created"

		echo "Function's files have been created"

		#Routine to deploy on Azure
		cd ..

		echo "Deploying the function"
		until func azure functionapp publish ${app}${id} --resource-group flyrg${id} --build-native-deps
		do
		    echo "Deploy attempt"
		done

		az  logout
		deactivate
	'''

	def CharSequence AzureUndeploy(Resource resource, String string, boolean local)'''
	'''

	def CharSequence AWSUndeploy(Resource resource, String string, boolean local,boolean debug)'''
	#!/bin/bash

			if [ $# -eq 0 ]
			  then
			    echo "No arguments supplied. ./aws_deploy.sh <user_profile> <function_name> <id_function_execution>"
			    exit 1
			fi

			user=$1
			function=$2
			id=$3

			# delete user queue
			«FOR res: resource.allContents.toIterable.filter(VariableDeclaration).filter[right instanceof DeclarationObject].filter[(it.right as DeclarationObject).features.get(0).value_s.equals("channel")]
			.filter[((it.environment.get(0) as VariableDeclaration).right as DeclarationObject).features.get(0).value_s.equals("aws")] »
				#get «res.name»_${id} queue-url

				echo "get «res.name»-${id} queue-url"
				queue_url=$(aws sqs --profile ${user} get-queue-url --queue-name «res.name»-${id} --query 'QueueUrl')
				echo ${queue_url//\"}

				echo "delete queue at url ${queue_url//\"} "
				aws sqs --profile ${user} delete-queue --queue-url ${queue_url//\"}

			«ENDFOR»

			«FOR  res: resource.allContents.toIterable.filter(FlyFunctionCall).filter[((it.environment as VariableDeclaration).right as DeclarationObject).features.get(0).value_s.equals("aws")]»
				#delete lambda function: «res.target.name»_${id}
				echo "delete lambda function: «res.target.name»_${id}"
				aws lambda --profile ${user} delete-function --function-name «res.target.name»_${id}

			«ENDFOR»
	'''

	def CharSequence AWSDebugUndeploy(Resource resource, String string, boolean local,boolean debug)'''
	#!/bin/bash

	# stop and remove localstack container
	docker-compose down

	# free some space used by localstack containers
	docker network rm mynet # mynet is created by docker-compose
	docker ps -a | awk '{ print $1,$2 }' | grep lambci/lambda:«language» | \
		awk '{print $1 }' | xargs -I {} docker rm {}

	echo "You may want to free additional space by running"
	echo -e "\tsudo rm -rf /tmp/_MEI*"
	'''

	def CharSequence compileScriptUndeploy(Resource resource, String name, boolean local){
		switch this.env {
			   case "aws": AWSUndeploy(resource,name,local,false)
			   case "aws-debug": AWSDebugUndeploy(resource,name,local,true)
			   case "azure": AzureUndeploy(resource,name,local)
			   default: this.env+" not supported"
			}
	}
}
