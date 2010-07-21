package net.riaspace.flerry
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	
	import mx.core.mx_internal;
	import mx.messaging.events.MessageFaultEvent;
	import mx.messaging.messages.AcknowledgeMessage;
	import mx.messaging.messages.ErrorMessage;
	import mx.messaging.messages.RemotingMessage;
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	
	use namespace flash_proxy;
	use namespace mx_internal;
	
	[DefaultProperty("methods")]
	
	[Event(name="result", type="mx.rpc.events.ResultEvent")]
	[Event(name="fault", type="mx.rpc.events.FaultEvent")]
	public dynamic class NativeObject extends Proxy implements IEventDispatcher
	{
		
		public static const STOP_PROCESS_HEADER:String = "STOP_PROCESS_HEADER";
		
		[Bindable]
		public var source:String;
		
		[Bindable]
		public var singleton:Boolean = false;
		
		[Bindable]
		public var binPath:String;
		
		[Bindable]
		public var startupInfoProvider:IStartupInfoProvider = new JavaStartupInfoProvider();
		
		protected var _methods:Array = new Array();
		
		protected var eventDispatcher:IEventDispatcher;
		
		protected var nativeProcess:NativeProcess;
		
		protected var tokens:Dictionary = new Dictionary();
		
		protected var messageBytes:ByteArray = new ByteArray();
		
		public function NativeObject(source:String = null, singleton:Boolean = false)
		{
			this.source = source;
			this.singleton = singleton;
			eventDispatcher = new EventDispatcher(this);
		}
		
		protected function initialize():void
		{
			var startupInfo:NativeProcessStartupInfo = startupInfoProvider.getStartupInfo(binPath, source, singleton);
			
			nativeProcess = new NativeProcess();
			nativeProcess.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, onOutputData);
			nativeProcess.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			
			nativeProcess.addEventListener(IOErrorEvent.STANDARD_INPUT_IO_ERROR, ioErrorInputError);
			nativeProcess.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, ioErrorInputError);
			nativeProcess.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, ioErrorInputError);
			
			nativeProcess.start(startupInfo);
		}
		
		protected function ioErrorInputError(event:IOErrorEvent):void
		{
			messageBytes.clear();
		}
		
		protected function onOutputData(event:ProgressEvent):void
		{
			nativeProcess.standardOutput.readBytes(
				messageBytes, messageBytes.length, nativeProcess.standardOutput.bytesAvailable);
			
			if ((messageBytes[messageBytes.length -1] == 99) &&  
				(messageBytes[messageBytes.length -2] == 99) && 
				(messageBytes[messageBytes.length -3] == 99) && 
				(messageBytes[messageBytes.length -4] == 99))
			{
				/* NOTE: messageBytes.readObject will IGNORE the marker bytes automatically, so no need to delete them */
				//create object from the collected bytes
				var message:AcknowledgeMessage = messageBytes.readObject() as AcknowledgeMessage;
				if (message && tokens[message.correlationId])
				{
					var token:AsyncToken = tokens[message.correlationId];
					delete tokens[message.correlationId];
					
					var resultEvent:ResultEvent = ResultEvent.createEvent(message.body, token, message);
					token.applyResult(resultEvent);
					
					var remotingMessage:RemotingMessage = token.message as RemotingMessage;
					if (remotingMessage)
					{
						var method:NativeMethod = _methods[remotingMessage.operation];
						if (method.hasEventListener(ResultEvent.RESULT))
							method.dispatchEvent(resultEvent);					
					}
					
					if (hasEventListener(ResultEvent.RESULT))
						dispatchEvent(resultEvent);
				}
				// if message isn't a response to a request then dispatch MessageEvent
				else if (message)
				{
					var msgEvent:MessageEvent = new MessageEvent(message.correlationId, message.body);					
					dispatchEvent(msgEvent);
				}
				messageBytes.clear();
			} 
		}
		
		protected function onErrorData(event:ProgressEvent):void
		{
			var buffer:ByteArray = new ByteArray();
			while (nativeProcess.standardError.bytesAvailable > 0){
				nativeProcess.standardError.readBytes(buffer, 
					buffer.length, nativeProcess.standardError.bytesAvailable);
			}
			var message:ErrorMessage = buffer.readObject() as ErrorMessage;

			if (message && message.correlationId)
			{
				var token:AsyncToken = tokens[message.correlationId];
				delete tokens[message.correlationId];
				
				var resultEvent:FaultEvent = FaultEvent.createEventFromMessageFault(MessageFaultEvent.createEvent(message), token);
				
				token.applyFault(resultEvent);
				
				var remotingMessage:RemotingMessage = token.message as RemotingMessage;
				if (remotingMessage)
				{
					var method:NativeMethod = _methods[remotingMessage.operation];
					if (method.hasEventListener(FaultEvent.FAULT))
						method.dispatchEvent(resultEvent);					
				}
				
				if (hasEventListener(FaultEvent.FAULT))
					dispatchEvent(resultEvent);
			} 
			else if (message)
			{
				throw new Error("NativeProcess error without correlationId: " + message);
			}
		}
		/**
		 * tries to close remote process
		 */
		public function exit():void{
			if(nativeProcess)
				nativeProcess.exit(true);
		}
		/**
		 * Subscribe to receive remote messages.
		 * @param String messageId
		 * @param Function(event:MessageEvent)
		 */
		public function subscribe(messageId:String, handler:Function):void{
			addEventListener(messageId,handler);
		}
		
		override flash_proxy function callProperty(methodName:*, ... args):* 
		{
			var method:NativeMethod = _methods[methodName];
			if (method == null)
			{
				method = new NativeMethod();
				method.name = methodName;
				_methods[methodName] = method;
			}
			return call(method, args);
		}
		
		protected function call(method:NativeMethod, ... args):AsyncToken
		{
			if (!nativeProcess)
				initialize();
			
			var message:RemotingMessage = new RemotingMessage();
			message.operation = method.name;
			message.source = source;
			message.headers = {SINGLETON_HEADER:singleton};
			
			if (args.length == 1)
			{
				message.body = args[0];
			}
			
			nativeProcess.standardInput.writeObject(message);
			
			var token:AsyncToken = new AsyncToken(message);
			tokens[message.messageId] = token;
			
			return token;
		}
		
		[Bindable]
		public function set methods(methods:Array):void
		{
			_methods = new Array();
			for each(var method:NativeMethod in methods)
			{
				_methods[method.name] = method;
			}
		}
		
		[ArrayElementType("net.riaspace.flerry.NativeMethod")]
		public function get methods():Array
		{
			return _methods;
		}
		
		/// ----------------------------------
		/// EventDispatcher functions
		/// ----------------------------------
		
		public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false):void
		{
			eventDispatcher.addEventListener(type, listener, useCapture, priority, useWeakReference);
		}
		
		public function dispatchEvent(event:Event):Boolean
		{
			return eventDispatcher.dispatchEvent(event);
		}
		
		public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false):void
		{
			eventDispatcher.removeEventListener(type, listener, useCapture);
		}
		
		public function hasEventListener(type:String):Boolean
		{
			return eventDispatcher.hasEventListener(type);
		}
		
		public function willTrigger(type:String):Boolean
		{
			return eventDispatcher.willTrigger(type);
		}
	}
}