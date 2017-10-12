//
//  GPBDictionary2.m
//  ProtocolBuffers
//
//  Created by Eric on 10/11/17.
//

#import "GPBDictionary_PackagePrivate.h"

#import "GPBCodedInputStream_PackagePrivate.h"
#import "GPBCodedOutputStream_PackagePrivate.h"
#import "GPBDescriptor_PackagePrivate.h"
#import "GPBMessage_PackagePrivate.h"
#import "GPBUtilities_PackagePrivate.h"

// ------------------------------ NOTE ------------------------------
// At the moment, this is all using NSNumbers in NSDictionaries under
// the hood, but it is all hidden so we can come back and optimize
// with direct CFDictionary usage later.  The reason that wasn't
// done yet is needing to support 32bit iOS builds.  Otherwise
// it would be pretty simple to store all this data in CFDictionaries
// directly.
// ------------------------------------------------------------------

// Direct access is use for speed, to avoid even internally declaring things
// read/write, etc. The warning is enabled in the project to ensure code calling
// protos can turn on -Wdirect-ivar-access without issues.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

// Used to include code only visible to specific versions of the static
// analyzer. Useful for wrapping code that only exists to silence the analyzer.
// Determine the values you want to use for BEGIN_APPLE_BUILD_VERSION,
// END_APPLE_BUILD_VERSION using:
//   xcrun clang -dM -E -x c /dev/null | grep __apple_build_version__
// Example usage:
//  #if GPB_STATIC_ANALYZER_ONLY(5621, 5623) ... #endif
#define GPB_STATIC_ANALYZER_ONLY(BEGIN_APPLE_BUILD_VERSION, END_APPLE_BUILD_VERSION) \
(defined(__clang_analyzer__) && \
(__apple_build_version__ >= BEGIN_APPLE_BUILD_VERSION && \
__apple_build_version__ <= END_APPLE_BUILD_VERSION))

enum {
    kMapKeyFieldNumber = 1,
    kMapValueFieldNumber = 2,
};

static BOOL DictDefault_IsValidValue(int32_t value) {
    // Anything but the bad value marker is allowed.
    return (value != kGPBUnrecognizedEnumeratorValue);
}

//%PDDM-DEFINE SERIALIZE_SUPPORT_2_TYPE(VALUE_NAME, VALUE_TYPE, GPBDATATYPE_NAME1, GPBDATATYPE_NAME2)
//%static size_t ComputeDict##VALUE_NAME##FieldSize(VALUE_TYPE value, uint32_t fieldNum, GPBDataType dataType) {
//%  if (dataType == GPBDataType##GPBDATATYPE_NAME1) {
//%    return GPBCompute##GPBDATATYPE_NAME1##Size(fieldNum, value);
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME2) {
//%    return GPBCompute##GPBDATATYPE_NAME2##Size(fieldNum, value);
//%  } else {
//%    NSCAssert(NO, @"Unexpected type %d", dataType);
//%    return 0;
//%  }
//%}
//%
//%static void WriteDict##VALUE_NAME##Field(GPBCodedOutputStream *stream, VALUE_TYPE value, uint32_t fieldNum, GPBDataType dataType) {
//%  if (dataType == GPBDataType##GPBDATATYPE_NAME1) {
//%    [stream write##GPBDATATYPE_NAME1##:fieldNum value:value];
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME2) {
//%    [stream write##GPBDATATYPE_NAME2##:fieldNum value:value];
//%  } else {
//%    NSCAssert(NO, @"Unexpected type %d", dataType);
//%  }
//%}
//%
//%PDDM-DEFINE SERIALIZE_SUPPORT_3_TYPE(VALUE_NAME, VALUE_TYPE, GPBDATATYPE_NAME1, GPBDATATYPE_NAME2, GPBDATATYPE_NAME3)
//%static size_t ComputeDict##VALUE_NAME##FieldSize(VALUE_TYPE value, uint32_t fieldNum, GPBDataType dataType) {
//%  if (dataType == GPBDataType##GPBDATATYPE_NAME1) {
//%    return GPBCompute##GPBDATATYPE_NAME1##Size(fieldNum, value);
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME2) {
//%    return GPBCompute##GPBDATATYPE_NAME2##Size(fieldNum, value);
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME3) {
//%    return GPBCompute##GPBDATATYPE_NAME3##Size(fieldNum, value);
//%  } else {
//%    NSCAssert(NO, @"Unexpected type %d", dataType);
//%    return 0;
//%  }
//%}
//%
//%static void WriteDict##VALUE_NAME##Field(GPBCodedOutputStream *stream, VALUE_TYPE value, uint32_t fieldNum, GPBDataType dataType) {
//%  if (dataType == GPBDataType##GPBDATATYPE_NAME1) {
//%    [stream write##GPBDATATYPE_NAME1##:fieldNum value:value];
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME2) {
//%    [stream write##GPBDATATYPE_NAME2##:fieldNum value:value];
//%  } else if (dataType == GPBDataType##GPBDATATYPE_NAME3) {
//%    [stream write##GPBDATATYPE_NAME3##:fieldNum value:value];
//%  } else {
//%    NSCAssert(NO, @"Unexpected type %d", dataType);
//%  }
//%}
//%
//%PDDM-DEFINE SIMPLE_SERIALIZE_SUPPORT(VALUE_NAME, VALUE_TYPE, VisP)
//%static size_t ComputeDict##VALUE_NAME##FieldSize(VALUE_TYPE VisP##value, uint32_t fieldNum, GPBDataType dataType) {
//%  NSCAssert(dataType == GPBDataType##VALUE_NAME, @"bad type: %d", dataType);
//%  #pragma unused(dataType)  // For when asserts are off in release.
//%  return GPBCompute##VALUE_NAME##Size(fieldNum, value);
//%}
//%
//%static void WriteDict##VALUE_NAME##Field(GPBCodedOutputStream *stream, VALUE_TYPE VisP##value, uint32_t fieldNum, GPBDataType dataType) {
//%  NSCAssert(dataType == GPBDataType##VALUE_NAME, @"bad type: %d", dataType);
//%  #pragma unused(dataType)  // For when asserts are off in release.
//%  [stream write##VALUE_NAME##:fieldNum value:value];
//%}
//%
//%PDDM-DEFINE SERIALIZE_SUPPORT_HELPERS()
//%SERIALIZE_SUPPORT_3_TYPE(Int32, int32_t, Int32, SInt32, SFixed32)
//%SERIALIZE_SUPPORT_2_TYPE(UInt32, uint32_t, UInt32, Fixed32)
//%SERIALIZE_SUPPORT_3_TYPE(Int64, int64_t, Int64, SInt64, SFixed64)
//%SERIALIZE_SUPPORT_2_TYPE(UInt64, uint64_t, UInt64, Fixed64)
//%SIMPLE_SERIALIZE_SUPPORT(Bool, BOOL, )
//%SIMPLE_SERIALIZE_SUPPORT(Enum, int32_t, )
//%SIMPLE_SERIALIZE_SUPPORT(Float, float, )
//%SIMPLE_SERIALIZE_SUPPORT(Double, double, )
//%SIMPLE_SERIALIZE_SUPPORT(String, NSString, *)
//%SERIALIZE_SUPPORT_3_TYPE(Object, id, Message, String, Bytes)
//%PDDM-EXPAND SERIALIZE_SUPPORT_HELPERS()
// This block of code is generated, do not edit it directly.

static size_t ComputeDictInt32FieldSize(int32_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeInt32) {
    return GPBComputeInt32Size(fieldNum, value);
  } else if (dataType == GPBDataTypeSInt32) {
    return GPBComputeSInt32Size(fieldNum, value);
  } else if (dataType == GPBDataTypeSFixed32) {
    return GPBComputeSFixed32Size(fieldNum, value);
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
    return 0;
  }
}

static void WriteDictInt32Field(GPBCodedOutputStream *stream, int32_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeInt32) {
    [stream writeInt32:fieldNum value:value];
  } else if (dataType == GPBDataTypeSInt32) {
    [stream writeSInt32:fieldNum value:value];
  } else if (dataType == GPBDataTypeSFixed32) {
    [stream writeSFixed32:fieldNum value:value];
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
  }
}

static size_t ComputeDictUInt32FieldSize(uint32_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeUInt32) {
    return GPBComputeUInt32Size(fieldNum, value);
  } else if (dataType == GPBDataTypeFixed32) {
    return GPBComputeFixed32Size(fieldNum, value);
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
    return 0;
  }
}

static void WriteDictUInt32Field(GPBCodedOutputStream *stream, uint32_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeUInt32) {
    [stream writeUInt32:fieldNum value:value];
  } else if (dataType == GPBDataTypeFixed32) {
    [stream writeFixed32:fieldNum value:value];
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
  }
}

static size_t ComputeDictInt64FieldSize(int64_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeInt64) {
    return GPBComputeInt64Size(fieldNum, value);
  } else if (dataType == GPBDataTypeSInt64) {
    return GPBComputeSInt64Size(fieldNum, value);
  } else if (dataType == GPBDataTypeSFixed64) {
    return GPBComputeSFixed64Size(fieldNum, value);
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
    return 0;
  }
}

static void WriteDictInt64Field(GPBCodedOutputStream *stream, int64_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeInt64) {
    [stream writeInt64:fieldNum value:value];
  } else if (dataType == GPBDataTypeSInt64) {
    [stream writeSInt64:fieldNum value:value];
  } else if (dataType == GPBDataTypeSFixed64) {
    [stream writeSFixed64:fieldNum value:value];
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
  }
}

static size_t ComputeDictUInt64FieldSize(uint64_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeUInt64) {
    return GPBComputeUInt64Size(fieldNum, value);
  } else if (dataType == GPBDataTypeFixed64) {
    return GPBComputeFixed64Size(fieldNum, value);
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
    return 0;
  }
}

static void WriteDictUInt64Field(GPBCodedOutputStream *stream, uint64_t value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeUInt64) {
    [stream writeUInt64:fieldNum value:value];
  } else if (dataType == GPBDataTypeFixed64) {
    [stream writeFixed64:fieldNum value:value];
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
  }
}

static size_t ComputeDictBoolFieldSize(BOOL value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeBool, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  return GPBComputeBoolSize(fieldNum, value);
}

static void WriteDictBoolField(GPBCodedOutputStream *stream, BOOL value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeBool, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  [stream writeBool:fieldNum value:value];
}

static size_t ComputeDictEnumFieldSize(int32_t value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeEnum, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  return GPBComputeEnumSize(fieldNum, value);
}

static void WriteDictEnumField(GPBCodedOutputStream *stream, int32_t value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeEnum, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  [stream writeEnum:fieldNum value:value];
}

static size_t ComputeDictFloatFieldSize(float value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeFloat, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  return GPBComputeFloatSize(fieldNum, value);
}

static void WriteDictFloatField(GPBCodedOutputStream *stream, float value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeFloat, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  [stream writeFloat:fieldNum value:value];
}

static size_t ComputeDictDoubleFieldSize(double value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeDouble, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  return GPBComputeDoubleSize(fieldNum, value);
}

static void WriteDictDoubleField(GPBCodedOutputStream *stream, double value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeDouble, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  [stream writeDouble:fieldNum value:value];
}

static size_t ComputeDictStringFieldSize(NSString *value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeString, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  return GPBComputeStringSize(fieldNum, value);
}

static void WriteDictStringField(GPBCodedOutputStream *stream, NSString *value, uint32_t fieldNum, GPBDataType dataType) {
  NSCAssert(dataType == GPBDataTypeString, @"bad type: %d", dataType);
  #pragma unused(dataType)  // For when asserts are off in release.
  [stream writeString:fieldNum value:value];
}

static size_t ComputeDictObjectFieldSize(id value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeMessage) {
    return GPBComputeMessageSize(fieldNum, value);
  } else if (dataType == GPBDataTypeString) {
    return GPBComputeStringSize(fieldNum, value);
  } else if (dataType == GPBDataTypeBytes) {
    return GPBComputeBytesSize(fieldNum, value);
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
    return 0;
  }
}

static void WriteDictObjectField(GPBCodedOutputStream *stream, id value, uint32_t fieldNum, GPBDataType dataType) {
  if (dataType == GPBDataTypeMessage) {
    [stream writeMessage:fieldNum value:value];
  } else if (dataType == GPBDataTypeString) {
    [stream writeString:fieldNum value:value];
  } else if (dataType == GPBDataTypeBytes) {
    [stream writeBytes:fieldNum value:value];
  } else {
    NSCAssert(NO, @"Unexpected type %d", dataType);
  }
}

//%PDDM-EXPAND-END SERIALIZE_SUPPORT_HELPERS()

size_t GPBDictionaryComputeSizeInternalHelper(NSDictionary *dict, GPBFieldDescriptor *field) {
    GPBDataType mapValueType = GPBGetFieldDataType(field);
    size_t result = 0;
    NSString *key;
    NSEnumerator *keys = [dict keyEnumerator];
    while ((key = [keys nextObject])) {
        id obj = dict[key];
        size_t msgSize = GPBComputeStringSize(kMapKeyFieldNumber, key);
        msgSize += ComputeDictObjectFieldSize(obj, kMapValueFieldNumber, mapValueType);
        result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
    }
    size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
    result += tagSize * dict.count;
    return result;
}

void GPBDictionaryWriteToStreamInternalHelper(GPBCodedOutputStream *outputStream,
                                              NSDictionary *dict,
                                              GPBFieldDescriptor *field) {
    NSCAssert(field.mapKeyDataType == GPBDataTypeString, @"Unexpected key type");
    GPBDataType mapValueType = GPBGetFieldDataType(field);
    uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
    NSString *key;
    NSEnumerator *keys = [dict keyEnumerator];
    while ((key = [keys nextObject])) {
        id obj = dict[key];
        // Write the tag.
        [outputStream writeInt32NoTag:tag];
        // Write the size of the message.
        size_t msgSize = GPBComputeStringSize(kMapKeyFieldNumber, key);
        msgSize += ComputeDictObjectFieldSize(obj, kMapValueFieldNumber, mapValueType);
        
        // Write the size and fields.
        [outputStream writeInt32NoTag:(int32_t)msgSize];
        [outputStream writeString:kMapKeyFieldNumber value:key];
        WriteDictObjectField(outputStream, obj, kMapValueFieldNumber, mapValueType);
    }
}

BOOL GPBDictionaryIsInitializedInternalHelper(NSDictionary *dict, GPBFieldDescriptor *field) {
    NSCAssert(field.mapKeyDataType == GPBDataTypeString, @"Unexpected key type");
    NSCAssert(GPBGetFieldDataType(field) == GPBDataTypeMessage, @"Unexpected value type");
#pragma unused(field)  // For when asserts are off in release.
    GPBMessage *msg;
    NSEnumerator *objects = [dict objectEnumerator];
    while ((msg = [objects nextObject])) {
        if (!msg.initialized) {
            return NO;
        }
    }
    return YES;
}

// Note: if the type is an object, it the retain pass back to the caller.
static void ReadValue(GPBCodedInputStream *stream,
                      GPBGenericValue *valueToFill,
                      GPBDataType type,
                      GPBExtensionRegistry *registry,
                      GPBFieldDescriptor *field) {
    switch (type) {
        case GPBDataTypeBool:
            valueToFill->valueBool = GPBCodedInputStreamReadBool(&stream->state_);
            break;
        case GPBDataTypeFixed32:
            valueToFill->valueUInt32 = GPBCodedInputStreamReadFixed32(&stream->state_);
            break;
        case GPBDataTypeSFixed32:
            valueToFill->valueInt32 = GPBCodedInputStreamReadSFixed32(&stream->state_);
            break;
        case GPBDataTypeFloat:
            valueToFill->valueFloat = GPBCodedInputStreamReadFloat(&stream->state_);
            break;
        case GPBDataTypeFixed64:
            valueToFill->valueUInt64 = GPBCodedInputStreamReadFixed64(&stream->state_);
            break;
        case GPBDataTypeSFixed64:
            valueToFill->valueInt64 = GPBCodedInputStreamReadSFixed64(&stream->state_);
            break;
        case GPBDataTypeDouble:
            valueToFill->valueDouble = GPBCodedInputStreamReadDouble(&stream->state_);
            break;
        case GPBDataTypeInt32:
            valueToFill->valueInt32 = GPBCodedInputStreamReadInt32(&stream->state_);
            break;
        case GPBDataTypeInt64:
            valueToFill->valueInt64 = GPBCodedInputStreamReadInt64(&stream->state_);
            break;
        case GPBDataTypeSInt32:
            valueToFill->valueInt32 = GPBCodedInputStreamReadSInt32(&stream->state_);
            break;
        case GPBDataTypeSInt64:
            valueToFill->valueInt64 = GPBCodedInputStreamReadSInt64(&stream->state_);
            break;
        case GPBDataTypeUInt32:
            valueToFill->valueUInt32 = GPBCodedInputStreamReadUInt32(&stream->state_);
            break;
        case GPBDataTypeUInt64:
            valueToFill->valueUInt64 = GPBCodedInputStreamReadUInt64(&stream->state_);
            break;
        case GPBDataTypeBytes:
            [valueToFill->valueData release];
            valueToFill->valueData = GPBCodedInputStreamReadRetainedBytes(&stream->state_);
            break;
        case GPBDataTypeString:
            [valueToFill->valueString release];
            valueToFill->valueString = GPBCodedInputStreamReadRetainedString(&stream->state_);
            break;
        case GPBDataTypeMessage: {
            GPBMessage *message = [[field.msgClass alloc] init];
            [stream readMessage:message extensionRegistry:registry];
            [valueToFill->valueMessage release];
            valueToFill->valueMessage = message;
            break;
        }
        case GPBDataTypeGroup:
            NSCAssert(NO, @"Can't happen");
            break;
        case GPBDataTypeEnum:
            valueToFill->valueEnum = GPBCodedInputStreamReadEnum(&stream->state_);
            break;
    }
}

void GPBDictionaryReadEntry(id mapDictionary,
                            GPBCodedInputStream *stream,
                            GPBExtensionRegistry *registry,
                            GPBFieldDescriptor *field,
                            GPBMessage *parentMessage) {
    GPBDataType keyDataType = field.mapKeyDataType;
    GPBDataType valueDataType = GPBGetFieldDataType(field);
    
    GPBGenericValue key;
    GPBGenericValue value;
    // Zero them (but pick up any enum default for proto2).
    key.valueString = value.valueString = nil;
    if (valueDataType == GPBDataTypeEnum) {
        value = field.defaultValue;
    }
    
    GPBCodedInputStreamState *state = &stream->state_;
    uint32_t keyTag =
    GPBWireFormatMakeTag(kMapKeyFieldNumber, GPBWireFormatForType(keyDataType, NO));
    uint32_t valueTag =
    GPBWireFormatMakeTag(kMapValueFieldNumber, GPBWireFormatForType(valueDataType, NO));
    
    BOOL hitError = NO;
    while (YES) {
        uint32_t tag = GPBCodedInputStreamReadTag(state);
        if (tag == keyTag) {
            ReadValue(stream, &key, keyDataType, registry, field);
        } else if (tag == valueTag) {
            ReadValue(stream, &value, valueDataType, registry, field);
        } else if (tag == 0) {
            // zero signals EOF / limit reached
            break;
        } else {  // Unknown
            if (![stream skipField:tag]){
                hitError = YES;
                break;
            }
        }
    }
    
    if (!hitError) {
        // Handle the special defaults and/or missing key/value.
        if ((keyDataType == GPBDataTypeString) && (key.valueString == nil)) {
            key.valueString = [@"" retain];
        }
        if (GPBDataTypeIsObject(valueDataType) && value.valueString == nil) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wswitch-enum"
            switch (valueDataType) {
                case GPBDataTypeString:
                    value.valueString = [@"" retain];
                    break;
                case GPBDataTypeBytes:
                    value.valueData = [GPBEmptyNSData() retain];
                    break;
#if defined(__clang_analyzer__)
                case GPBDataTypeGroup:
                    // Maps can't really have Groups as the value type, but this case is needed
                    // so the analyzer won't report the posibility of send nil in for the value
                    // in the NSMutableDictionary case below.
#endif
                case GPBDataTypeMessage: {
                    value.valueMessage = [[field.msgClass alloc] init];
                    break;
                }
                default:
                    // Nothing
                    break;
            }
#pragma clang diagnostic pop
        }
        
        if ((keyDataType == GPBDataTypeString) && GPBDataTypeIsObject(valueDataType)) {
#if GPB_STATIC_ANALYZER_ONLY(6020053, 7000181)
            // Limited to Xcode 6.4 - 7.2, are known to fail here. The upper end can
            // be raised as needed for new Xcodes.
            //
            // This is only needed on a "shallow" analyze; on a "deep" analyze, the
            // existing code path gets this correct. In shallow, the analyzer decides
            // GPBDataTypeIsObject(valueDataType) is both false and true on a single
            // path through this function, allowing nil to be used for the
            // setObject:forKey:.
            if (value.valueString == nil) {
                value.valueString = [@"" retain];
            }
#endif
            // mapDictionary is an NSMutableDictionary
            [(NSMutableDictionary *)mapDictionary setObject:value.valueString
                                                     forKey:key.valueString];
        } else {
            if (valueDataType == GPBDataTypeEnum) {
                if (GPBHasPreservingUnknownEnumSemantics([parentMessage descriptor].file.syntax) ||
                    [field isValidEnumValue:value.valueEnum]) {
                    [mapDictionary setGPBGenericValue:&value forGPBGenericValueKey:&key];
                } else {
                    NSData *data = [mapDictionary serializedDataForUnknownValue:value.valueEnum
                                                                         forKey:&key
                                                                    keyDataType:keyDataType];
                    [parentMessage addUnknownMapEntry:GPBFieldNumber(field) value:data];
                }
            } else {
                [mapDictionary setGPBGenericValue:&value forGPBGenericValueKey:&key];
            }
        }
    }
    
    if (GPBDataTypeIsObject(keyDataType)) {
        [key.valueString release];
    }
    if (GPBDataTypeIsObject(valueDataType)) {
        [value.valueString release];
    }
}

void initHelper(NSMutableDictionary *dictionary, NSUInteger count, ) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
        for (NSUInteger i = 0; i < count; ++i) {
            [_dictionary setObject:@(values[i]) forKey:@(keys[i])];
        }
    }
}

//
// Macros for the common basic cases.
//

//%PDDM-DEFINE DICTIONARY_IMPL_FOR_POD_KEY(KEY_NAME, KEY_TYPE)
//%DICTIONARY_POD_IMPL_FOR_KEY(KEY_NAME, KEY_TYPE, , POD)
//%DICTIONARY_POD_KEY_TO_OBJECT_IMPL(KEY_NAME, KEY_TYPE, Object, id)

//%PDDM-DEFINE DICTIONARY_POD_IMPL_FOR_KEY(KEY_NAME, KEY_TYPE, KisP, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, UInt32, uint32_t, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, Int32, int32_t, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, UInt64, uint64_t, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, Int64, int64_t, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, Bool, BOOL, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, Float, float, KHELPER)
//%DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, Double, double, KHELPER)
//%DICTIONARY_KEY_TO_ENUM_IMPL(KEY_NAME, KEY_TYPE, KisP, Enum, int32_t, KHELPER)

//%PDDM-DEFINE DICTIONARY_KEY_TO_POD_IMPL(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER)
//%DICTIONARY_COMMON_IMPL(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, POD, VALUE_NAME, value)

//%PDDM-DEFINE DICTIONARY_POD_KEY_TO_OBJECT_IMPL(KEY_NAME, KEY_TYPE, VALUE_NAME, VALUE_TYPE)
//%DICTIONARY_COMMON_IMPL(KEY_NAME, KEY_TYPE, , VALUE_NAME, VALUE_TYPE, POD, OBJECT, Object, object)

//%PDDM-DEFINE DICTIONARY_COMMON_IMPL(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_VAR)
//%#pragma mark - KEY_NAME -> VALUE_NAME
//%
//%@implementation GPB##KEY_NAME##VALUE_NAME##Dictionary {
//% @package
//%  NSMutableDictionary *_dictionary;
//%}
//%
//%+ (instancetype)dictionary {
//%  return [[[self alloc] initWith##VNAME##s:NULL forKeys:NULL count:0] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWith##VNAME##:(VALUE_TYPE)##VNAME_VAR
//%                      ##VNAME$S##  forKey:(KEY_TYPE##KisP$S##KisP)key {
//%  // Cast is needed so the compiler knows what class we are invoking initWith##VNAME##s:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWith##VNAME##s:&##VNAME_VAR
//%               KEY_NAME$S VALUE_NAME$S                        ##VNAME$S##  forKeys:&key
//%               KEY_NAME$S VALUE_NAME$S                        ##VNAME$S##    count:1] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWith##VNAME##s:(const VALUE_TYPE [])##VNAME_VAR##s
//%                      ##VNAME$S##  forKeys:(const KEY_TYPE##KisP$S##KisP [])keys
//%                      ##VNAME$S##    count:(NSUInteger)count {
//%  // Cast is needed so the compiler knows what class we are invoking initWith##VNAME##s:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWith##VNAME##s:##VNAME_VAR##s
//%               KEY_NAME$S VALUE_NAME$S                               forKeys:keys
//%               KEY_NAME$S VALUE_NAME$S                                 count:count] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithDictionary:(GPB##KEY_NAME##VALUE_NAME##Dictionary *)dictionary {
//%  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
//%  return [[[self alloc] initWithCapacity:numItems] autorelease];
//%}
//%
//%- (instancetype)init {
//%  return [self initWith##VNAME##s:NULL forKeys:NULL count:0];
//%}
//%
//%- (instancetype)initWith##VNAME##s:(const VALUE_TYPE [])##VNAME_VAR##s
//%                ##VNAME$S##  forKeys:(const KEY_TYPE##KisP$S##KisP [])keys
//%                ##VNAME$S##    count:(NSUInteger)count {
//%  self = [super init];
//%  if (self) {
//%    _dictionary = [[NSMutableDictionary alloc] init];
//%    if (count && VNAME_VAR##s && keys) {
//%      for (NSUInteger i = 0; i < count; ++i) {
//%DICTIONARY_VALIDATE_VALUE_##VHELPER(VNAME_VAR##s[i], ______)##DICTIONARY_VALIDATE_KEY_##KHELPER(keys[i], ______)        [_dictionary setObject:WRAPPED##VHELPER(VNAME_VAR##s[i]) forKey:WRAPPED##KHELPER(keys[i])];
//%      }
//%    }
//%  }
//%  return self;
//%}
//%
//%- (instancetype)initWithDictionary:(GPB##KEY_NAME##VALUE_NAME##Dictionary *)dictionary {
//%  self = [self initWith##VNAME##s:NULL forKeys:NULL count:0];
//%  if (self) {
//%    if (dictionary) {
//%      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
//%    }
//%  }
//%  return self;
//%}
//%
//%- (instancetype)initWithCapacity:(NSUInteger)numItems {
//%  #pragma unused(numItems)
//%  return [self initWith##VNAME##s:NULL forKeys:NULL count:0];
//%}
//%
//%DICTIONARY_IMMUTABLE_CORE(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_VAR, )
//%
//%VALUE_FOR_KEY_##VHELPER(KEY_TYPE##KisP$S##KisP, VALUE_NAME, VALUE_TYPE, KHELPER)
//%
//%DICTIONARY_MUTABLE_CORE(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_VAR, )
//%
//%@end
//%

//%PDDM-DEFINE DICTIONARY_KEY_TO_ENUM_IMPL(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER)
//%DICTIONARY_KEY_TO_ENUM_IMPL2(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, POD)
//%PDDM-DEFINE DICTIONARY_KEY_TO_ENUM_IMPL2(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER)
//%#pragma mark - KEY_NAME -> VALUE_NAME
//%
//%@implementation GPB##KEY_NAME##VALUE_NAME##Dictionary {
//% @package
//%  NSMutableDictionary *_dictionary;
//%  GPBEnumValidationFunc _validationFunc;
//%}
//%
//%@synthesize validationFunc = _validationFunc;
//%
//%+ (instancetype)dictionary {
//%  return [[[self alloc] initWithValidationFunction:NULL
//%                                         rawValues:NULL
//%                                           forKeys:NULL
//%                                             count:0] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func {
//%  return [[[self alloc] initWithValidationFunction:func
//%                                         rawValues:NULL
//%                                           forKeys:NULL
//%                                             count:0] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
//%                                        rawValue:(VALUE_TYPE)rawValue
//%                                          forKey:(KEY_TYPE##KisP$S##KisP)key {
//%  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWithValidationFunction:func
//%               KEY_NAME$S VALUE_NAME$S                                         rawValues:&rawValue
//%               KEY_NAME$S VALUE_NAME$S                                           forKeys:&key
//%               KEY_NAME$S VALUE_NAME$S                                             count:1] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
//%                                       rawValues:(const VALUE_TYPE [])rawValues
//%                                         forKeys:(const KEY_TYPE##KisP$S##KisP [])keys
//%                                           count:(NSUInteger)count {
//%  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWithValidationFunction:func
//%               KEY_NAME$S VALUE_NAME$S                                         rawValues:rawValues
//%               KEY_NAME$S VALUE_NAME$S                                           forKeys:keys
//%               KEY_NAME$S VALUE_NAME$S                                             count:count] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithDictionary:(GPB##KEY_NAME##VALUE_NAME##Dictionary *)dictionary {
//%  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPB##KEY_NAME##VALUE_NAME##Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
//%                                        capacity:(NSUInteger)numItems {
//%  return [[[self alloc] initWithValidationFunction:func capacity:numItems] autorelease];
//%}
//%
//%- (instancetype)init {
//%  return [self initWithValidationFunction:NULL rawValues:NULL forKeys:NULL count:0];
//%}
//%
//%- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func {
//%  return [self initWithValidationFunction:func rawValues:NULL forKeys:NULL count:0];
//%}
//%
//%- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
//%                                 rawValues:(const VALUE_TYPE [])rawValues
//%                                   forKeys:(const KEY_TYPE##KisP$S##KisP [])keys
//%                                     count:(NSUInteger)count {
//%  self = [super init];
//%  if (self) {
//%    _dictionary = [[NSMutableDictionary alloc] init];
//%    _validationFunc = (func != NULL ? func : DictDefault_IsValidValue);
//%    if (count && rawValues && keys) {
//%      for (NSUInteger i = 0; i < count; ++i) {
//%DICTIONARY_VALIDATE_KEY_##KHELPER(keys[i], ______)        [_dictionary setObject:WRAPPED##VHELPER(rawValues[i]) forKey:WRAPPED##KHELPER(keys[i])];
//%      }
//%    }
//%  }
//%  return self;
//%}
//%
//%- (instancetype)initWithDictionary:(GPB##KEY_NAME##VALUE_NAME##Dictionary *)dictionary {
//%  self = [self initWithValidationFunction:dictionary.validationFunc
//%                                rawValues:NULL
//%                                  forKeys:NULL
//%                                    count:0];
//%  if (self) {
//%    if (dictionary) {
//%      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
//%    }
//%  }
//%  return self;
//%}
//%
//%- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
//%                                  capacity:(NSUInteger)numItems {
//%  #pragma unused(numItems)
//%  return [self initWithValidationFunction:func rawValues:NULL forKeys:NULL count:0];
//%}
//%
//%DICTIONARY_IMMUTABLE_CORE(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, Value, value, Raw)
//%
//%- (BOOL)getEnum:(VALUE_TYPE *)value forKey:(KEY_TYPE##KisP$S##KisP)key {
//%  NSNumber *wrapped = [_dictionary objectForKey:WRAPPED##KHELPER(key)];
//%  if (wrapped && value) {
//%    VALUE_TYPE result = UNWRAP##VALUE_NAME(wrapped);
//%    if (!_validationFunc(result)) {
//%      result = kGPBUnrecognizedEnumeratorValue;
//%    }
//%    *value = result;
//%  }
//%  return (wrapped != NULL);
//%}
//%
//%- (BOOL)getRawValue:(VALUE_TYPE *)rawValue forKey:(KEY_TYPE##KisP$S##KisP)key {
//%  NSNumber *wrapped = [_dictionary objectForKey:WRAPPED##KHELPER(key)];
//%  if (wrapped && rawValue) {
//%    *rawValue = UNWRAP##VALUE_NAME(wrapped);
//%  }
//%  return (wrapped != NULL);
//%}
//%
//%- (void)enumerateKeysAndEnumsUsingBlock:
//%    (void (^)(KEY_TYPE KisP##key, VALUE_TYPE value, BOOL *stop))block {
//%  GPBEnumValidationFunc func = _validationFunc;
//%  BOOL stop = NO;
//%  NSEnumerator *keys = [_dictionary keyEnumerator];
//%  ENUM_TYPE##KHELPER(KEY_TYPE)##aKey;
//%  while ((aKey = [keys nextObject])) {
//%    ENUM_TYPE##VHELPER(VALUE_TYPE)##aValue = _dictionary[aKey];
//%      VALUE_TYPE unwrapped = UNWRAP##VALUE_NAME(aValue);
//%      if (!func(unwrapped)) {
//%        unwrapped = kGPBUnrecognizedEnumeratorValue;
//%      }
//%    block(UNWRAP##KEY_NAME(aKey), unwrapped, &stop);
//%    if (stop) {
//%      break;
//%    }
//%  }
//%}
//%
//%DICTIONARY_MUTABLE_CORE2(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, Value, Enum, value, Raw)
//%
//%- (void)setEnum:(VALUE_TYPE)value forKey:(KEY_TYPE##KisP$S##KisP)key {
//%DICTIONARY_VALIDATE_KEY_##KHELPER(key, )  if (!_validationFunc(value)) {
//%    [NSException raise:NSInvalidArgumentException
//%                format:@"GPB##KEY_NAME##VALUE_NAME##Dictionary: Attempt to set an unknown enum value (%d)",
//%                       value];
//%  }
//%
//%  [_dictionary setObject:WRAPPED##VHELPER(value) forKey:WRAPPED##KHELPER(key)];
//%  if (_autocreator) {
//%    GPBAutocreatedDictionaryModified(_autocreator, self);
//%  }
//%}
//%
//%@end
//%

//%PDDM-DEFINE DICTIONARY_IMMUTABLE_CORE(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_VAR, ACCESSOR_NAME)
//%- (void)dealloc {
//%  NSAssert(!_autocreator,
//%           @"%@: Autocreator must be cleared before release, autocreator: %@",
//%           [self class], _autocreator);
//%  [_dictionary release];
//%  [super dealloc];
//%}
//%
//%- (instancetype)copyWithZone:(NSZone *)zone {
//%  return [[GPB##KEY_NAME##VALUE_NAME##Dictionary allocWithZone:zone] initWithDictionary:self];
//%}
//%
//%- (BOOL)isEqual:(id)other {
//%  if (self == other) {
//%    return YES;
//%  }
//%  if (![other isKindOfClass:[GPB##KEY_NAME##VALUE_NAME##Dictionary class]]) {
//%    return NO;
//%  }
//%  GPB##KEY_NAME##VALUE_NAME##Dictionary *otherDictionary = other;
//%  return [_dictionary isEqual:otherDictionary->_dictionary];
//%}
//%
//%- (NSUInteger)hash {
//%  return _dictionary.count;
//%}
//%
//%- (NSString *)description {
//%  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
//%}
//%
//%- (NSUInteger)count {
//%  return _dictionary.count;
//%}
//%
//%- (void)enumerateKeysAnd##ACCESSOR_NAME##VNAME##sUsingBlock:
//%    (void (^)(KEY_TYPE KisP##key, VALUE_TYPE VNAME_VAR, BOOL *stop))block {
//%  BOOL stop = NO;
//%  NSDictionary *internal = _dictionary;
//%  NSEnumerator *keys = [internal keyEnumerator];
//%  ENUM_TYPE##KHELPER(KEY_TYPE)##aKey;
//%  while ((aKey = [keys nextObject])) {
//%    ENUM_TYPE##VHELPER(VALUE_TYPE)##a##VNAME_VAR$u = internal[aKey];
//%    block(UNWRAP##KEY_NAME(aKey), UNWRAP##VALUE_NAME(a##VNAME_VAR$u), &stop);
//%    if (stop) {
//%      break;
//%    }
//%  }
//%}
//%
//%EXTRA_METHODS_##VHELPER(KEY_NAME, VALUE_NAME)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
//%  NSDictionary *internal = _dictionary;
//%  NSUInteger count = internal.count;
//%  if (count == 0) {
//%    return 0;
//%  }
//%
//%  GPBDataType valueDataType = GPBGetFieldDataType(field);
//%  GPBDataType keyDataType = field.mapKeyDataType;
//%  size_t result = 0;
//%  NSEnumerator *keys = [internal keyEnumerator];
//%  ENUM_TYPE##KHELPER(KEY_TYPE)##aKey;
//%  while ((aKey = [keys nextObject])) {
//%    ENUM_TYPE##VHELPER(VALUE_TYPE)##a##VNAME_VAR$u = internal[aKey];
//%    size_t msgSize = ComputeDict##KEY_NAME##FieldSize(UNWRAP##KEY_NAME(aKey), kMapKeyFieldNumber, keyDataType);
//%    msgSize += ComputeDict##VALUE_NAME##FieldSize(UNWRAP##VALUE_NAME(a##VNAME_VAR$u), kMapValueFieldNumber, valueDataType);
//%    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
//%  }
//%  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
//%  result += tagSize * count;
//%  return result;
//%}
//%
//%- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
//%                         asField:(GPBFieldDescriptor *)field {
//%  GPBDataType valueDataType = GPBGetFieldDataType(field);
//%  GPBDataType keyDataType = field.mapKeyDataType;
//%  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
//%  NSDictionary *internal = _dictionary;
//%  NSEnumerator *keys = [internal keyEnumerator];
//%  ENUM_TYPE##KHELPER(KEY_TYPE)##aKey;
//%  while ((aKey = [keys nextObject])) {
//%    ENUM_TYPE##VHELPER(VALUE_TYPE)##a##VNAME_VAR$u = internal[aKey];
//%    [outputStream writeInt32NoTag:tag];
//%    // Write the size of the message.
//%    KEY_TYPE KisP##unwrappedKey = UNWRAP##KEY_NAME(aKey);
//%    VALUE_TYPE unwrappedValue = UNWRAP##VALUE_NAME(a##VNAME_VAR$u);
//%    size_t msgSize = ComputeDict##KEY_NAME##FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
//%    msgSize += ComputeDict##VALUE_NAME##FieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
//%    [outputStream writeInt32NoTag:(int32_t)msgSize];
//%    // Write the fields.
//%    WriteDict##KEY_NAME##Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
//%    WriteDict##VALUE_NAME##Field(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
//%  }
//%}
//%
//%SERIAL_DATA_FOR_ENTRY_##VHELPER(KEY_NAME, VALUE_NAME)- (void)setGPBGenericValue:(GPBGenericValue *)value
//%     forGPBGenericValueKey:(GPBGenericValue *)key {
//%  [_dictionary setObject:WRAPPED##VHELPER(value->##GPBVALUE_##VHELPER(VALUE_NAME)##) forKey:WRAPPED##KHELPER(key->value##KEY_NAME)];
//%}
//%
//%- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
//%  [self enumerateKeysAnd##ACCESSOR_NAME##VNAME##sUsingBlock:^(KEY_TYPE KisP##key, VALUE_TYPE VNAME_VAR, BOOL *stop) {
//%      #pragma unused(stop)
//%      block(TEXT_FORMAT_OBJ##KEY_NAME(key), TEXT_FORMAT_OBJ##VALUE_NAME(VNAME_VAR));
//%  }];
//%}
//%PDDM-DEFINE DICTIONARY_MUTABLE_CORE(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_VAR, ACCESSOR_NAME)
//%DICTIONARY_MUTABLE_CORE2(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME, VNAME_VAR, ACCESSOR_NAME)
//%PDDM-DEFINE DICTIONARY_MUTABLE_CORE2(KEY_NAME, KEY_TYPE, KisP, VALUE_NAME, VALUE_TYPE, KHELPER, VHELPER, VNAME, VNAME_REMOVE, VNAME_VAR, ACCESSOR_NAME)
//%- (void)add##ACCESSOR_NAME##EntriesFromDictionary:(GPB##KEY_NAME##VALUE_NAME##Dictionary *)otherDictionary {
//%  if (otherDictionary) {
//%    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
//%    if (_autocreator) {
//%      GPBAutocreatedDictionaryModified(_autocreator, self);
//%    }
//%  }
//%}
//%
//%- (void)set##ACCESSOR_NAME##VNAME##:(VALUE_TYPE)VNAME_VAR forKey:(KEY_TYPE##KisP$S##KisP)key {
//%DICTIONARY_VALIDATE_VALUE_##VHELPER(VNAME_VAR, )##DICTIONARY_VALIDATE_KEY_##KHELPER(key, )  [_dictionary setObject:WRAPPED##VHELPER(VNAME_VAR) forKey:WRAPPED##KHELPER(key)];
//%  if (_autocreator) {
//%    GPBAutocreatedDictionaryModified(_autocreator, self);
//%  }
//%}
//%
//%- (void)remove##VNAME_REMOVE##ForKey:(KEY_TYPE##KisP$S##KisP)aKey {
//%  [_dictionary removeObjectForKey:WRAPPED##KHELPER(aKey)];
//%}
//%
//%- (void)removeAll {
//%  [_dictionary removeAllObjects];
//%}

//
// Custom Generation for Bool keys
//

//%PDDM-DEFINE DICTIONARY_BOOL_KEY_TO_POD_IMPL(VALUE_NAME, VALUE_TYPE)
//%DICTIONARY_BOOL_KEY_TO_VALUE_IMPL(VALUE_NAME, VALUE_TYPE, POD, VALUE_NAME, value)
//%PDDM-DEFINE DICTIONARY_BOOL_KEY_TO_OBJECT_IMPL(VALUE_NAME, VALUE_TYPE)
//%DICTIONARY_BOOL_KEY_TO_VALUE_IMPL(VALUE_NAME, VALUE_TYPE, OBJECT, Object, object)

//%PDDM-DEFINE DICTIONARY_BOOL_KEY_TO_VALUE_IMPL(VALUE_NAME, VALUE_TYPE, HELPER, VNAME, VNAME_VAR)
//%#pragma mark - Bool -> VALUE_NAME
//%
//%@implementation GPBBool##VALUE_NAME##Dictionary {
//% @package
//%  VALUE_TYPE _values[2];
//%BOOL_DICT_HAS_STORAGE_##HELPER()}
//%
//%+ (instancetype)dictionary {
//%  return [[[self alloc] initWith##VNAME##s:NULL forKeys:NULL count:0] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWith##VNAME##:(VALUE_TYPE)VNAME_VAR
//%                      ##VNAME$S##  forKey:(BOOL)key {
//%  // Cast is needed so the compiler knows what class we are invoking initWith##VNAME##s:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPBBool##VALUE_NAME##Dictionary*)[self alloc] initWith##VNAME##s:&##VNAME_VAR
//%                    VALUE_NAME$S                        ##VNAME$S##  forKeys:&key
//%                    VALUE_NAME$S                        ##VNAME$S##    count:1] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWith##VNAME##s:(const VALUE_TYPE [])##VNAME_VAR##s
//%                      ##VNAME$S##  forKeys:(const BOOL [])keys
//%                      ##VNAME$S##    count:(NSUInteger)count {
//%  // Cast is needed so the compiler knows what class we are invoking initWith##VNAME##s:forKeys:count:
//%  // on to get the type correct.
//%  return [[(GPBBool##VALUE_NAME##Dictionary*)[self alloc] initWith##VNAME##s:##VNAME_VAR##s
//%                    VALUE_NAME$S                        ##VNAME$S##  forKeys:keys
//%                    VALUE_NAME$S                        ##VNAME$S##    count:count] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithDictionary:(GPBBool##VALUE_NAME##Dictionary *)dictionary {
//%  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
//%  // on to get the type correct.
//%  return [[(GPBBool##VALUE_NAME##Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
//%}
//%
//%+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
//%  return [[[self alloc] initWithCapacity:numItems] autorelease];
//%}
//%
//%- (instancetype)init {
//%  return [self initWith##VNAME##s:NULL forKeys:NULL count:0];
//%}
//%
//%BOOL_DICT_INITS_##HELPER(VALUE_NAME, VALUE_TYPE)
//%
//%- (instancetype)initWithCapacity:(NSUInteger)numItems {
//%  #pragma unused(numItems)
//%  return [self initWith##VNAME##s:NULL forKeys:NULL count:0];
//%}
//%
//%BOOL_DICT_DEALLOC##HELPER()
//%
//%- (instancetype)copyWithZone:(NSZone *)zone {
//%  return [[GPBBool##VALUE_NAME##Dictionary allocWithZone:zone] initWithDictionary:self];
//%}
//%
//%- (BOOL)isEqual:(id)other {
//%  if (self == other) {
//%    return YES;
//%  }
//%  if (![other isKindOfClass:[GPBBool##VALUE_NAME##Dictionary class]]) {
//%    return NO;
//%  }
//%  GPBBool##VALUE_NAME##Dictionary *otherDictionary = other;
//%  if ((BOOL_DICT_W_HAS##HELPER(0, ) != BOOL_DICT_W_HAS##HELPER(0, otherDictionary->)) ||
//%      (BOOL_DICT_W_HAS##HELPER(1, ) != BOOL_DICT_W_HAS##HELPER(1, otherDictionary->))) {
//%    return NO;
//%  }
//%  if ((BOOL_DICT_W_HAS##HELPER(0, ) && (NEQ_##HELPER(_values[0], otherDictionary->_values[0]))) ||
//%      (BOOL_DICT_W_HAS##HELPER(1, ) && (NEQ_##HELPER(_values[1], otherDictionary->_values[1])))) {
//%    return NO;
//%  }
//%  return YES;
//%}
//%
//%- (NSUInteger)hash {
//%  return (BOOL_DICT_W_HAS##HELPER(0, ) ? 1 : 0) + (BOOL_DICT_W_HAS##HELPER(1, ) ? 1 : 0);
//%}
//%
//%- (NSString *)description {
//%  NSMutableString *result = [NSMutableString stringWithFormat:@"<%@ %p> {", [self class], self];
//%  if (BOOL_DICT_W_HAS##HELPER(0, )) {
//%    [result appendFormat:@"NO: STR_FORMAT_##HELPER(VALUE_NAME)", _values[0]];
//%  }
//%  if (BOOL_DICT_W_HAS##HELPER(1, )) {
//%    [result appendFormat:@"YES: STR_FORMAT_##HELPER(VALUE_NAME)", _values[1]];
//%  }
//%  [result appendString:@" }"];
//%  return result;
//%}
//%
//%- (NSUInteger)count {
//%  return (BOOL_DICT_W_HAS##HELPER(0, ) ? 1 : 0) + (BOOL_DICT_W_HAS##HELPER(1, ) ? 1 : 0);
//%}
//%
//%BOOL_VALUE_FOR_KEY_##HELPER(VALUE_NAME, VALUE_TYPE)
//%
//%BOOL_SET_GPBVALUE_FOR_KEY_##HELPER(VALUE_NAME, VALUE_TYPE, VisP)
//%
//%- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
//%  if (BOOL_DICT_HAS##HELPER(0, )) {
//%    block(@"false", TEXT_FORMAT_OBJ##VALUE_NAME(_values[0]));
//%  }
//%  if (BOOL_DICT_W_HAS##HELPER(1, )) {
//%    block(@"true", TEXT_FORMAT_OBJ##VALUE_NAME(_values[1]));
//%  }
//%}
//%
//%- (void)enumerateKeysAnd##VNAME##sUsingBlock:
//%    (void (^)(BOOL key, VALUE_TYPE VNAME_VAR, BOOL *stop))block {
//%  BOOL stop = NO;
//%  if (BOOL_DICT_HAS##HELPER(0, )) {
//%    block(NO, _values[0], &stop);
//%  }
//%  if (!stop && BOOL_DICT_W_HAS##HELPER(1, )) {
//%    block(YES, _values[1], &stop);
//%  }
//%}
//%
//%BOOL_EXTRA_METHODS_##HELPER(Bool, VALUE_NAME)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
//%  GPBDataType valueDataType = GPBGetFieldDataType(field);
//%  NSUInteger count = 0;
//%  size_t result = 0;
//%  for (int i = 0; i < 2; ++i) {
//%    if (BOOL_DICT_HAS##HELPER(i, )) {
//%      ++count;
//%      size_t msgSize = ComputeDictBoolFieldSize((i == 1), kMapKeyFieldNumber, GPBDataTypeBool);
//%      msgSize += ComputeDict##VALUE_NAME##FieldSize(_values[i], kMapValueFieldNumber, valueDataType);
//%      result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
//%    }
//%  }
//%  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
//%  result += tagSize * count;
//%  return result;
//%}
//%
//%- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
//%                         asField:(GPBFieldDescriptor *)field {
//%  GPBDataType valueDataType = GPBGetFieldDataType(field);
//%  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
//%  for (int i = 0; i < 2; ++i) {
//%    if (BOOL_DICT_HAS##HELPER(i, )) {
//%      // Write the tag.
//%      [outputStream writeInt32NoTag:tag];
//%      // Write the size of the message.
//%      size_t msgSize = ComputeDictBoolFieldSize((i == 1), kMapKeyFieldNumber, GPBDataTypeBool);
//%      msgSize += ComputeDict##VALUE_NAME##FieldSize(_values[i], kMapValueFieldNumber, valueDataType);
//%      [outputStream writeInt32NoTag:(int32_t)msgSize];
//%      // Write the fields.
//%      WriteDictBoolField(outputStream, (i == 1), kMapKeyFieldNumber, GPBDataTypeBool);
//%      WriteDict##VALUE_NAME##Field(outputStream, _values[i], kMapValueFieldNumber, valueDataType);
//%    }
//%  }
//%}
//%
//%BOOL_DICT_MUTATIONS_##HELPER(VALUE_NAME, VALUE_TYPE)
//%
//%@end
//%

//%PDDM-EXPAND DICTIONARY_IMPL_FOR_POD_KEY(UInt32, uint32_t)
// This block of code is generated, do not edit it directly.

#pragma mark - UInt32 -> UInt32

@implementation GPBUInt32UInt32Dictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithUInt32s:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithUInt32:(uint32_t)value
                              forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithUInt32s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32UInt32Dictionary*)[self alloc] initWithUInt32s:&value
                                                            forKeys:&key
                                                              count:1] autorelease];
}

+ (instancetype)dictionaryWithUInt32s:(const uint32_t [])values
                              forKeys:(const uint32_t [])keys
                                count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithUInt32s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32UInt32Dictionary*)[self alloc] initWithUInt32s:values
                                                           forKeys:keys
                                                             count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32UInt32Dictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32UInt32Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithUInt32s:NULL forKeys:NULL count:0];
}

- (instancetype)initWithUInt32s:(const uint32_t [])values
                        forKeys:(const uint32_t [])keys
                          count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32UInt32Dictionary *)dictionary {
  self = [self initWithUInt32s:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithUInt32s:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32UInt32Dictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32UInt32Dictionary class]]) {
    return NO;
  }
  GPBUInt32UInt32Dictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndUInt32sUsingBlock:
    (void (^)(uint32_t key, uint32_t value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint32_t)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPUInt32(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, UInt32)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint32_t)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictUInt32FieldSize(UNWRAPUInt32(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint32_t)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    uint32_t unwrappedValue = UNWRAPUInt32(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictUInt32FieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictUInt32Field(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, UInt32)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(UInt32)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndUInt32sUsingBlock:^(uint32_t key, uint32_t value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJUInt32(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, UInt32, uint32_t, POD)

- (void)addEntriesFromDictionary:(GPBUInt32UInt32Dictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setUInt32:(uint32_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeUInt32ForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Int32

@implementation GPBUInt32Int32Dictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithInt32s:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithInt32:(int32_t)value
                             forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithInt32s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32Int32Dictionary*)[self alloc] initWithInt32s:&value
                                                          forKeys:&key
                                                            count:1] autorelease];
}

+ (instancetype)dictionaryWithInt32s:(const int32_t [])values
                             forKeys:(const uint32_t [])keys
                               count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithInt32s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32Int32Dictionary*)[self alloc] initWithInt32s:values
                                                          forKeys:keys
                                                            count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32Int32Dictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32Int32Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithInt32s:NULL forKeys:NULL count:0];
}

- (instancetype)initWithInt32s:(const int32_t [])values
                       forKeys:(const uint32_t [])keys
                         count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32Int32Dictionary *)dictionary {
  self = [self initWithInt32s:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithInt32s:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32Int32Dictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32Int32Dictionary class]]) {
    return NO;
  }
  GPBUInt32Int32Dictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndInt32sUsingBlock:
    (void (^)(uint32_t key, int32_t value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPInt32(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Int32)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictInt32FieldSize(UNWRAPInt32(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    int32_t unwrappedValue = UNWRAPInt32(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictInt32FieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictInt32Field(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Int32)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Int32)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndInt32sUsingBlock:^(uint32_t key, int32_t value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJInt32(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, Int32, int32_t, POD)

- (void)addEntriesFromDictionary:(GPBUInt32Int32Dictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setInt32:(int32_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeInt32ForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> UInt64

@implementation GPBUInt32UInt64Dictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithUInt64s:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithUInt64:(uint64_t)value
                              forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithUInt64s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32UInt64Dictionary*)[self alloc] initWithUInt64s:&value
                                                            forKeys:&key
                                                              count:1] autorelease];
}

+ (instancetype)dictionaryWithUInt64s:(const uint64_t [])values
                              forKeys:(const uint32_t [])keys
                                count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithUInt64s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32UInt64Dictionary*)[self alloc] initWithUInt64s:values
                                                           forKeys:keys
                                                             count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32UInt64Dictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32UInt64Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithUInt64s:NULL forKeys:NULL count:0];
}

- (instancetype)initWithUInt64s:(const uint64_t [])values
                        forKeys:(const uint32_t [])keys
                          count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32UInt64Dictionary *)dictionary {
  self = [self initWithUInt64s:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithUInt64s:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32UInt64Dictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32UInt64Dictionary class]]) {
    return NO;
  }
  GPBUInt32UInt64Dictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndUInt64sUsingBlock:
    (void (^)(uint32_t key, uint64_t value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint64_t)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPUInt64(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, UInt64)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint64_t)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictUInt64FieldSize(UNWRAPUInt64(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(uint64_t)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    uint64_t unwrappedValue = UNWRAPUInt64(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictUInt64FieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictUInt64Field(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, UInt64)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(UInt64)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndUInt64sUsingBlock:^(uint32_t key, uint64_t value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJUInt64(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, UInt64, uint64_t, POD)

- (void)addEntriesFromDictionary:(GPBUInt32UInt64Dictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setUInt64:(uint64_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeUInt64ForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Int64

@implementation GPBUInt32Int64Dictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithInt64s:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithInt64:(int64_t)value
                             forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithInt64s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32Int64Dictionary*)[self alloc] initWithInt64s:&value
                                                          forKeys:&key
                                                            count:1] autorelease];
}

+ (instancetype)dictionaryWithInt64s:(const int64_t [])values
                             forKeys:(const uint32_t [])keys
                               count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithInt64s:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32Int64Dictionary*)[self alloc] initWithInt64s:values
                                                          forKeys:keys
                                                            count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32Int64Dictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32Int64Dictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithInt64s:NULL forKeys:NULL count:0];
}

- (instancetype)initWithInt64s:(const int64_t [])values
                       forKeys:(const uint32_t [])keys
                         count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32Int64Dictionary *)dictionary {
  self = [self initWithInt64s:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithInt64s:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32Int64Dictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32Int64Dictionary class]]) {
    return NO;
  }
  GPBUInt32Int64Dictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndInt64sUsingBlock:
    (void (^)(uint32_t key, int64_t value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int64_t)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPInt64(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Int64)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int64_t)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictInt64FieldSize(UNWRAPInt64(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int64_t)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    int64_t unwrappedValue = UNWRAPInt64(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictInt64FieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictInt64Field(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Int64)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Int64)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndInt64sUsingBlock:^(uint32_t key, int64_t value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJInt64(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, Int64, int64_t, POD)

- (void)addEntriesFromDictionary:(GPBUInt32Int64Dictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setInt64:(int64_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeInt64ForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Bool

@implementation GPBUInt32BoolDictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithBools:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithBool:(BOOL)value
                            forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithBools:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32BoolDictionary*)[self alloc] initWithBools:&value
                                                        forKeys:&key
                                                          count:1] autorelease];
}

+ (instancetype)dictionaryWithBools:(const BOOL [])values
                            forKeys:(const uint32_t [])keys
                              count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithBools:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32BoolDictionary*)[self alloc] initWithBools:values
                                                         forKeys:keys
                                                           count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32BoolDictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32BoolDictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithBools:NULL forKeys:NULL count:0];
}

- (instancetype)initWithBools:(const BOOL [])values
                      forKeys:(const uint32_t [])keys
                        count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32BoolDictionary *)dictionary {
  self = [self initWithBools:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithBools:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32BoolDictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32BoolDictionary class]]) {
    return NO;
  }
  GPBUInt32BoolDictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndBoolsUsingBlock:
    (void (^)(uint32_t key, BOOL value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(BOOL)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPBool(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Bool)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(BOOL)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictBoolFieldSize(UNWRAPBool(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(BOOL)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    BOOL unwrappedValue = UNWRAPBool(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictBoolFieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictBoolField(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Bool)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Bool)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndBoolsUsingBlock:^(uint32_t key, BOOL value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJBool(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, Bool, BOOL, POD)

- (void)addEntriesFromDictionary:(GPBUInt32BoolDictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setBool:(BOOL)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeBoolForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Float

@implementation GPBUInt32FloatDictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithFloats:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithFloat:(float)value
                             forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithFloats:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32FloatDictionary*)[self alloc] initWithFloats:&value
                                                          forKeys:&key
                                                            count:1] autorelease];
}

+ (instancetype)dictionaryWithFloats:(const float [])values
                             forKeys:(const uint32_t [])keys
                               count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithFloats:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32FloatDictionary*)[self alloc] initWithFloats:values
                                                          forKeys:keys
                                                            count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32FloatDictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32FloatDictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithFloats:NULL forKeys:NULL count:0];
}

- (instancetype)initWithFloats:(const float [])values
                       forKeys:(const uint32_t [])keys
                         count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32FloatDictionary *)dictionary {
  self = [self initWithFloats:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithFloats:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32FloatDictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32FloatDictionary class]]) {
    return NO;
  }
  GPBUInt32FloatDictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndFloatsUsingBlock:
    (void (^)(uint32_t key, float value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(float)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPFloat(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Float)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(float)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictFloatFieldSize(UNWRAPFloat(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(float)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    float unwrappedValue = UNWRAPFloat(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictFloatFieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictFloatField(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Float)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Float)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndFloatsUsingBlock:^(uint32_t key, float value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJFloat(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, Float, float, POD)

- (void)addEntriesFromDictionary:(GPBUInt32FloatDictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setFloat:(float)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeFloatForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Double

@implementation GPBUInt32DoubleDictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithDoubles:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithDouble:(double)value
                              forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithDoubles:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32DoubleDictionary*)[self alloc] initWithDoubles:&value
                                                            forKeys:&key
                                                              count:1] autorelease];
}

+ (instancetype)dictionaryWithDoubles:(const double [])values
                              forKeys:(const uint32_t [])keys
                                count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithDoubles:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32DoubleDictionary*)[self alloc] initWithDoubles:values
                                                           forKeys:keys
                                                             count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32DoubleDictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32DoubleDictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithDoubles:NULL forKeys:NULL count:0];
}

- (instancetype)initWithDoubles:(const double [])values
                        forKeys:(const uint32_t [])keys
                          count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && values && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_POD(values[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(values[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32DoubleDictionary *)dictionary {
  self = [self initWithDoubles:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithDoubles:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32DoubleDictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32DoubleDictionary class]]) {
    return NO;
  }
  GPBUInt32DoubleDictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndDoublesUsingBlock:
    (void (^)(uint32_t key, double value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(double)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPDouble(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Double)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(double)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictDoubleFieldSize(UNWRAPDouble(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(double)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    double unwrappedValue = UNWRAPDouble(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictDoubleFieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictDoubleField(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Double)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Double)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndDoublesUsingBlock:^(uint32_t key, double value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJDouble(value));
  }];
}

VALUE_FOR_KEY_POD(uint32_t, Double, double, POD)

- (void)addEntriesFromDictionary:(GPBUInt32DoubleDictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setDouble:(double)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeDoubleForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

#pragma mark - UInt32 -> Enum

@implementation GPBUInt32EnumDictionary {
 @package
  NSMutableDictionary *_dictionary;
  GPBEnumValidationFunc _validationFunc;
}

@synthesize validationFunc = _validationFunc;

+ (instancetype)dictionary {
  return [[[self alloc] initWithValidationFunction:NULL
                                         rawValues:NULL
                                           forKeys:NULL
                                             count:0] autorelease];
}

+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func {
  return [[[self alloc] initWithValidationFunction:func
                                         rawValues:NULL
                                           forKeys:NULL
                                             count:0] autorelease];
}

+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
                                        rawValue:(int32_t)rawValue
                                          forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32EnumDictionary*)[self alloc] initWithValidationFunction:func
                                                                   rawValues:&rawValue
                                                                     forKeys:&key
                                                                       count:1] autorelease];
}

+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
                                       rawValues:(const int32_t [])rawValues
                                         forKeys:(const uint32_t [])keys
                                           count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32EnumDictionary*)[self alloc] initWithValidationFunction:func
                                                                   rawValues:rawValues
                                                                     forKeys:keys
                                                                       count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32EnumDictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithValues:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32EnumDictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithValidationFunction:(GPBEnumValidationFunc)func
                                        capacity:(NSUInteger)numItems {
  return [[[self alloc] initWithValidationFunction:func capacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithValidationFunction:NULL rawValues:NULL forKeys:NULL count:0];
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func {
  return [self initWithValidationFunction:func rawValues:NULL forKeys:NULL count:0];
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                 rawValues:(const int32_t [])rawValues
                                   forKeys:(const uint32_t [])keys
                                     count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    _validationFunc = (func != NULL ? func : DictDefault_IsValidValue);
    if (count && rawValues && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDPOD(rawValues[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32EnumDictionary *)dictionary {
  self = [self initWithValidationFunction:dictionary.validationFunc
                                rawValues:NULL
                                  forKeys:NULL
                                    count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                  capacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithValidationFunction:func rawValues:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32EnumDictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32EnumDictionary class]]) {
    return NO;
  }
  GPBUInt32EnumDictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndRawValuesUsingBlock:
    (void (^)(uint32_t key, int32_t value, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPEnum(aValue), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_POD(UInt32, Enum)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictEnumFieldSize(UNWRAPEnum(aValue), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    int32_t unwrappedValue = UNWRAPEnum(aValue);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictEnumFieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictEnumField(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_POD(UInt32, Enum)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDPOD(value->GPBVALUE_POD(Enum)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndRawValuesUsingBlock:^(uint32_t key, int32_t value, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJEnum(value));
  }];
}

- (BOOL)getEnum:(int32_t *)value forKey:(uint32_t)key {
  NSNumber *wrapped = [_dictionary objectForKey:WRAPPEDPOD(key)];
  if (wrapped && value) {
    int32_t result = UNWRAPEnum(wrapped);
    if (!_validationFunc(result)) {
      result = kGPBUnrecognizedEnumeratorValue;
    }
    *value = result;
  }
  return (wrapped != NULL);
}

- (BOOL)getRawValue:(int32_t *)rawValue forKey:(uint32_t)key {
  NSNumber *wrapped = [_dictionary objectForKey:WRAPPEDPOD(key)];
  if (wrapped && rawValue) {
    *rawValue = UNWRAPEnum(wrapped);
  }
  return (wrapped != NULL);
}

- (void)enumerateKeysAndEnumsUsingBlock:
    (void (^)(uint32_t key, int32_t value, BOOL *stop))block {
  GPBEnumValidationFunc func = _validationFunc;
  BOOL stop = NO;
  NSEnumerator *keys = [_dictionary keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEPOD(int32_t)aValue = _dictionary[aKey];
      int32_t unwrapped = UNWRAPEnum(aValue);
      if (!func(unwrapped)) {
        unwrapped = kGPBUnrecognizedEnumeratorValue;
      }
    block(UNWRAPUInt32(aKey), unwrapped, &stop);
    if (stop) {
      break;
    }
  }
}

- (void)addRawEntriesFromDictionary:(GPBUInt32EnumDictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setRawValue:(int32_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_POD(value, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeEnumForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

- (void)setEnum:(int32_t)value forKey:(uint32_t)key {
DICTIONARY_VALIDATE_KEY_POD(key, )  if (!_validationFunc(value)) {
    [NSException raise:NSInvalidArgumentException
                format:@"GPBUInt32EnumDictionary: Attempt to set an unknown enum value (%d)",
                       value];
  }

  [_dictionary setObject:WRAPPEDPOD(value) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

@end

#pragma mark - UInt32 -> Object

@implementation GPBUInt32ObjectDictionary {
 @package
  NSMutableDictionary *_dictionary;
}

+ (instancetype)dictionary {
  return [[[self alloc] initWithObjects:NULL forKeys:NULL count:0] autorelease];
}

+ (instancetype)dictionaryWithObject:(id)object
                              forKey:(uint32_t)key {
  // Cast is needed so the compiler knows what class we are invoking initWithObjects:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32ObjectDictionary*)[self alloc] initWithObjects:&object
                                                            forKeys:&key
                                                              count:1] autorelease];
}

+ (instancetype)dictionaryWithObjects:(const id [])objects
                              forKeys:(const uint32_t [])keys
                                count:(NSUInteger)count {
  // Cast is needed so the compiler knows what class we are invoking initWithObjects:forKeys:count:
  // on to get the type correct.
  return [[(GPBUInt32ObjectDictionary*)[self alloc] initWithObjects:objects
                                                           forKeys:keys
                                                             count:count] autorelease];
}

+ (instancetype)dictionaryWithDictionary:(GPBUInt32ObjectDictionary *)dictionary {
  // Cast is needed so the compiler knows what class we are invoking initWithDictionary:
  // on to get the type correct.
  return [[(GPBUInt32ObjectDictionary*)[self alloc] initWithDictionary:dictionary] autorelease];
}

+ (instancetype)dictionaryWithCapacity:(NSUInteger)numItems {
  return [[[self alloc] initWithCapacity:numItems] autorelease];
}

- (instancetype)init {
  return [self initWithObjects:NULL forKeys:NULL count:0];
}

- (instancetype)initWithObjects:(const id [])objects
                        forKeys:(const uint32_t [])keys
                          count:(NSUInteger)count {
  self = [super init];
  if (self) {
    _dictionary = [[NSMutableDictionary alloc] init];
    if (count && objects && keys) {
      for (NSUInteger i = 0; i < count; ++i) {
DICTIONARY_VALIDATE_VALUE_OBJECT(objects[i], ______)DICTIONARY_VALIDATE_KEY_POD(keys[i], ______)        [_dictionary setObject:WRAPPEDOBJECT(objects[i]) forKey:WRAPPEDPOD(keys[i])];
      }
    }
  }
  return self;
}

- (instancetype)initWithDictionary:(GPBUInt32ObjectDictionary *)dictionary {
  self = [self initWithObjects:NULL forKeys:NULL count:0];
  if (self) {
    if (dictionary) {
      [_dictionary addEntriesFromDictionary:dictionary->_dictionary];
    }
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  #pragma unused(numItems)
  return [self initWithObjects:NULL forKeys:NULL count:0];
}

- (void)dealloc {
  NSAssert(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_dictionary release];
  [super dealloc];
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32ObjectDictionary allocWithZone:zone] initWithDictionary:self];
}

- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32ObjectDictionary class]]) {
    return NO;
  }
  GPBUInt32ObjectDictionary *otherDictionary = other;
  return [_dictionary isEqual:otherDictionary->_dictionary];
}

- (NSUInteger)hash {
  return _dictionary.count;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@ %p> { %@ }", [self class], self, _dictionary];
}

- (NSUInteger)count {
  return _dictionary.count;
}

- (void)enumerateKeysAndObjectsUsingBlock:
    (void (^)(uint32_t key, id object, BOOL *stop))block {
  BOOL stop = NO;
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEOBJECT(id)aObject = internal[aKey];
    block(UNWRAPUInt32(aKey), UNWRAPObject(aObject), &stop);
    if (stop) {
      break;
    }
  }
}

EXTRA_METHODS_OBJECT(UInt32, Object)- (size_t)computeSerializedSizeAsField:(GPBFieldDescriptor *)field {
  NSDictionary *internal = _dictionary;
  NSUInteger count = internal.count;
  if (count == 0) {
    return 0;
  }

  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  size_t result = 0;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEOBJECT(id)aObject = internal[aKey];
    size_t msgSize = ComputeDictUInt32FieldSize(UNWRAPUInt32(aKey), kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictObjectFieldSize(UNWRAPObject(aObject), kMapValueFieldNumber, valueDataType);
    result += GPBComputeRawVarint32SizeForInteger(msgSize) + msgSize;
  }
  size_t tagSize = GPBComputeWireFormatTagSize(GPBFieldNumber(field), GPBDataTypeMessage);
  result += tagSize * count;
  return result;
}

- (void)writeToCodedOutputStream:(GPBCodedOutputStream *)outputStream
                         asField:(GPBFieldDescriptor *)field {
  GPBDataType valueDataType = GPBGetFieldDataType(field);
  GPBDataType keyDataType = field.mapKeyDataType;
  uint32_t tag = GPBWireFormatMakeTag(GPBFieldNumber(field), GPBWireFormatLengthDelimited);
  NSDictionary *internal = _dictionary;
  NSEnumerator *keys = [internal keyEnumerator];
  ENUM_TYPEPOD(uint32_t)aKey;
  while ((aKey = [keys nextObject])) {
    ENUM_TYPEOBJECT(id)aObject = internal[aKey];
    [outputStream writeInt32NoTag:tag];
    // Write the size of the message.
    uint32_t unwrappedKey = UNWRAPUInt32(aKey);
    id unwrappedValue = UNWRAPObject(aObject);
    size_t msgSize = ComputeDictUInt32FieldSize(unwrappedKey, kMapKeyFieldNumber, keyDataType);
    msgSize += ComputeDictObjectFieldSize(unwrappedValue, kMapValueFieldNumber, valueDataType);
    [outputStream writeInt32NoTag:(int32_t)msgSize];
    // Write the fields.
    WriteDictUInt32Field(outputStream, unwrappedKey, kMapKeyFieldNumber, keyDataType);
    WriteDictObjectField(outputStream, unwrappedValue, kMapValueFieldNumber, valueDataType);
  }
}

SERIAL_DATA_FOR_ENTRY_OBJECT(UInt32, Object)- (void)setGPBGenericValue:(GPBGenericValue *)value
     forGPBGenericValueKey:(GPBGenericValue *)key {
  [_dictionary setObject:WRAPPEDOBJECT(value->GPBVALUE_OBJECT(Object)) forKey:WRAPPEDPOD(key->valueUInt32)];
}

- (void)enumerateForTextFormat:(void (^)(id keyObj, id valueObj))block {
  [self enumerateKeysAndObjectsUsingBlock:^(uint32_t key, id object, BOOL *stop) {
      #pragma unused(stop)
      block(TEXT_FORMAT_OBJUInt32(key), TEXT_FORMAT_OBJObject(object));
  }];
}

VALUE_FOR_KEY_OBJECT(uint32_t, Object, id, POD)

- (void)addEntriesFromDictionary:(GPBUInt32ObjectDictionary *)otherDictionary {
  if (otherDictionary) {
    [_dictionary addEntriesFromDictionary:otherDictionary->_dictionary];
    if (_autocreator) {
      GPBAutocreatedDictionaryModified(_autocreator, self);
    }
  }
}

- (void)setObject:(id)object forKey:(uint32_t)key {
DICTIONARY_VALIDATE_VALUE_OBJECT(object, )DICTIONARY_VALIDATE_KEY_POD(key, )  [_dictionary setObject:WRAPPEDOBJECT(object) forKey:WRAPPEDPOD(key)];
  if (_autocreator) {
    GPBAutocreatedDictionaryModified(_autocreator, self);
  }
}

- (void)removeObjectForKey:(uint32_t)aKey {
  [_dictionary removeObjectForKey:WRAPPEDPOD(aKey)];
}

- (void)removeAll {
  [_dictionary removeAllObjects];
}

@end

//%PDDM-EXPAND-END DICTIONARY_IMPL_FOR_POD_KEY(UInt32, uint32_t)

