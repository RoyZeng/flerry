The aim of this project is to simplify connectivity between Flex and Java applications using Adobe AIR 2.0 NativeProcess API. It brings additional API's very similar to standard Flex RemoteObject. It has full AS3-Java objects mapping based on AMF serialization taken from BlazeDS.

Code from Flerry Demo application:
```
<?xml version="1.0" encoding="utf-8"?>
<s:WindowedApplication xmlns:fx="http://ns.adobe.com/mxml/2009" 
			   xmlns:s="library://ns.adobe.com/flex/spark" 
			   xmlns:mx="library://ns.adobe.com/flex/mx" minWidth="300" minHeight="200" xmlns:flerry="net.riaspace.flerry.*">
	<fx:Script>
		<![CDATA[
			import flash.events.MouseEvent;
			
			import mx.controls.Alert;
			import mx.rpc.events.FaultEvent;
			import mx.rpc.events.ResultEvent;

			protected function nativeObject_faultHandler(event:FaultEvent):void
			{
				Alert.show(event.message.toString());
			}

			protected function addMethod_resultHandler(event:ResultEvent):void
			{
				txtResult.text = event.result.toString();
			}

			protected function btnAdd_clickHandler(event:MouseEvent):void
			{
				nativeObject.add(parseInt(txtValue1.text), parseInt(txtValue2.text));
			}

		]]>
	</fx:Script>
	<fx:Declarations>
		<flerry:NativeObject id="nativeObject" source="net.riaspace.flerrydemo.MyJavaObject" fault="nativeObject_faultHandler(event)">
			<flerry:NativeMethod id="addMethod" name="add" result="addMethod_resultHandler(event)" />
		</flerry:NativeObject> 
	</fx:Declarations>
	
	<s:HGroup verticalAlign="middle" textAlign="center" horizontalCenter="0" verticalCenter="0">
		<s:TextInput id="txtValue1" text="2" width="30" />
		<s:Label text="+" width="30" />
		<s:TextInput id="txtValue2" text="3" width="30" />
		<s:Button id="btnAdd" label="=" width="30" click="btnAdd_clickHandler(event)" />
		<s:TextInput id="txtResult" width="30" editable="false" />
	</s:HGroup>
	
</s:WindowedApplication>

```

Java code that is called from Flex:
```
package net.riaspace.flerrydemo;

public class MyJavaObject
{
	public MyJavaObject(){}
	
	public Integer add(Integer value1, Integer value2)
	{
		return value1 + value2;
	}
}
```