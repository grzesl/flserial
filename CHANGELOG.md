## 0.3.0
* Import project to new plugin ffi template
* Few Api changes

## 0.2.0
* New event model
* Cleaning up unnecessary libs
* Performance improvements
* Api changes, main functions:

Stream based events, before:
```
serial.onSerialData.subscribe(
```
to:
```
serial.onSerialData.stream.listen(
```

Write serial port, before:
```
serial.write(data.length, data);     
```
to:
```
serial.write(data);    
```

## 0.1.2
* Android compilation

## 0.1.1
* Initial beta version
