// Protocol Buffers - Google's data interchange format
// Copyright 2015 Google Inc.  All rights reserved.
// https://developers.google.com/protocol-buffers/
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//     * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import "GPBArray_PackagePrivate.h"

#import "GPBMessage_PackagePrivate.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

#define kChunkSize 16
#define CapacityFromCount(x) (((x / kChunkSize) + 1) * kChunkSize)
static BOOL ArrayDefault_IsValidValue(int32_t value) {
  // Anything but the bad value marker is allowed.
  return (value != kGPBUnrecognizedEnumeratorValue);
}

typedef struct GPBContext {
    char *_values;
    NSUInteger _count;
    NSUInteger _capacity;
    unsigned int _valueSize;
} GPBContext;


static id GPBArrayHelper_array(Class cls) {
  return [[cls alloc] init];
}

static id GPBArrayHelper_initWithValues(GPBContext *context, id self,const char * values,
                                                          NSUInteger count) {
  if (self) {
    if (count && values) {
      context->_values = (char *)reallocf(context->_values, count * context->_valueSize);
      if (context->_values != NULL) {
        context->_capacity = count;
        memcpy(context->_values, values, count * context->_valueSize);
        context->_count = count;
      } else {
        [self release];
        [NSException raise:NSMallocException
                    format:@"Failed to allocate %lu bytes",
         (unsigned long)(count * context->_valueSize)];
      }
    }
  }
  return self;
}

static void GPBArrayHelper_internalResizeToCapacity(GPBContext *context, NSUInteger newCapacity) {
  context->_values = (char *)reallocf(context->_values, newCapacity * context->_valueSize);
  if (context->_values == NULL) {
    context->_capacity = 0;
    context->_count = 0;
    [NSException raise:NSMallocException
                format:@"Failed to allocate %lu bytes",
     (unsigned long)(newCapacity * context->_valueSize)];
  }
  context->_capacity = newCapacity;
}

static BOOL GPBArrayHelper_isEqual(GPBContext *context, const GPBContext *otherArray) {
  
  return (context->_count == otherArray->_count
          && context->_valueSize == otherArray->_valueSize && memcmp(context->_values, otherArray->_values, (context->_count * context->_valueSize)) == 0);
}
static NSString * GPBArrayHelper_description(GPBContext *context, id obj,NSString *format) {
  NSMutableString *result = [NSMutableString stringWithFormat:@"<%@ %p> { ", [obj class], obj];
  for (NSUInteger i = 0, count = context->_count; i < count; ++i) {
      if (i == 0) {
        [result appendFormat:format, context->_values + context->_valueSize * i];
       } else {
         [result appendFormat:[@", " stringByAppendingString:format], context->_values + context->_valueSize * i];
       }
  
  }
  [result appendFormat:@" }"];
  return result;
}

static void GPBArrayHelper_enumerateValuesWithOptions(GPBContext *context, NSEnumerationOptions opts,
  void (^block)(const char *value, NSUInteger idx, BOOL *stop)){
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
  BOOL stop = NO;
  if ((opts & NSEnumerationReverse) == 0) {
    for (NSUInteger i = 0, count = context->_count; i < count; ++i) {
      block(context->_values + context->_valueSize * i, i, &stop);
      if (stop) break;
    }
  } else if (context->_count > 0) {
    for (NSUInteger i = context->_count; i > 0; --i) {
      block(context->_values + context->_valueSize * (i - 1), (i - 1), &stop);
      if (stop) break;
    }
  }
}
static void GPBArrayHelper_valueAtIndex(GPBContext *context, NSUInteger index,char * buffer){
  if (index >= context->_count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)context->_count];
  }
  memmove(buffer,context->_values + context->_valueSize * index,context->_valueSize);
}

static void GPBArrayHelper_addValues(GPBContext *context, const char * values,NSUInteger count) {
  if (values == NULL || count == 0) return;
  NSUInteger initialCount = context->_count;
  NSUInteger newCount = initialCount + count;
  if (newCount > context->_capacity) {
    GPBArrayHelper_internalResizeToCapacity(context,CapacityFromCount(newCount));
  }
  context->_count = newCount;
  memcpy(&context->_values[initialCount * context->_valueSize], values, count * context->_valueSize);
}
static void GPBArrayHelper_insertValue(GPBContext *context, const char * value,NSUInteger index) {
  if (index >= context->_count + 1) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)context->_count + 1];
  }
  NSUInteger initialCount = context->_count;
  NSUInteger newCount = initialCount + 1;
  if (newCount > context->_capacity) {
    GPBArrayHelper_internalResizeToCapacity(context,CapacityFromCount(newCount));
  }
  context->_count = newCount;
  if (index != initialCount) {
    memmove(&context->_values[(index + 1) * context->_valueSize], &context->_values[index * context->_valueSize], (initialCount - index) * context->_valueSize);
  }
  memmove(context->_values + index * context->_valueSize,value,context->_valueSize);
}

static void GPBArrayHelper_replaceValueAtIndex(GPBContext *context, NSUInteger index,const char *value) {
  if (index >= context->_count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)context->_count];
  }
  //_values[index] = value;
    memmove(context->_values + index * context->_valueSize, value, context->_valueSize);
}

static void GPBArrayHelper_removeValueAtIndex(GPBContext *context, NSUInteger index) {
  if (index >= context->_count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)index, (unsigned long)context->_count];
  }
  NSUInteger newCount = context->_count - 1;
  if (index != newCount) {
    memmove(&context->_values[index * context->_valueSize], &context->_values[(index + 1) * context->_valueSize], (newCount - index) * context->_valueSize);
  }
  context->_count = newCount;
  if ((newCount + (2 * kChunkSize)) < context->_capacity) {
    GPBArrayHelper_internalResizeToCapacity(context,CapacityFromCount(newCount));
  }
}

static void GPBArrayHelper_removeAll(GPBContext *context) {
  context->_count = 0;
  if ((0 + (2 * kChunkSize)) < context->_capacity) {
    GPBArrayHelper_internalResizeToCapacity(context,CapacityFromCount(0));
  }
}
static void GPBArrayHelper_exchangeValueAtIndex(GPBContext *context, NSUInteger idx1,NSUInteger idx2){
  if (idx1 >= context->_count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx1, (unsigned long)context->_count];
  }
  if (idx2 >= context->_count) {
    [NSException raise:NSRangeException
                format:@"Index (%lu) beyond bounds (%lu)",
     (unsigned long)idx2, (unsigned long)context->_count];
  }
    char * temp = (char *)malloc(context->_valueSize);
    memcpy(temp,context->_values + idx1 * context->_valueSize,context->_valueSize);
    memcpy(context->_values + context->_valueSize * idx1, context->_values + context->_valueSize * idx2, context->_valueSize);
    memcpy(context->_values + context->_valueSize * idx2, temp,context->_valueSize);
    free(temp);
  //_values[idx1] = _values[idx2];
  //_values[idx2] = temp;
}
//%PDDM-DEFINE DEFINE_ARRAY(LABEL,TYPE,STORAGE,FORMAT)
//%@implementation GPB##LABEL##Array {
//%  @package
//%  GPBContext _context;
//%}
//%- (NSUInteger)count {
//%  return _context._count;
//%}
//%+ (instancetype)array {
//%  return [GPBArrayHelper_array(self) autorelease];
//%}
//%+ (instancetype)arrayWithValue:(TYPE)value {
//%  return [[(GPB##LABEL##Array*)[self alloc] initWithValues:(TYPE *)&value count:1] autorelease];
//%}
//%+ (instancetype)arrayWithValueArray:(GPB##LABEL##Array *)array {
//%  return [[(GPB##LABEL##Array*)[self alloc] initWithValueArray:array] autorelease];
//%}
//%+ (instancetype)arrayWithCapacity:(NSUInteger)count {
//%  return [[[self alloc] initWithCapacity:count] autorelease];
//%}
//%- (instancetype)init {
//%  self = [super init];
//%  if (self) {
//%     _context._valueSize = sizeof(TYPE);
//%  }
//%  return self;
//%}
//%- (instancetype)initWithValueArray:(GPB##LABEL##Array *)array {
//%  return [self initWithValues:(TYPE *)array->_context._values count:array->_context._count];
//%}
//%- (instancetype)initWithValues:(const TYPE[])values count:(NSUInteger)count {
//%  self = [self init];
//%  if (self) {
//%    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
//%  }
//%  return self;
//%}
//%- (instancetype)initWithCapacity:(NSUInteger)count {
//%  self = [self initWithValues:NULL count:0];
//%  if (self && count) {
//%  GPBArrayHelper_internalResizeToCapacity(&_context,count);
//%  }
//%  return self;
//%}
//%- (instancetype)copyWithZone:(NSZone *)zone {
//%  return [[GPB##LABEL##Array allocWithZone:zone] initWithValues:(TYPE *)self->_context._values count:self->_context._count];
//%}
//%- (void)dealloc {
//%  NSAssert2(!_autocreator,
//%         @"%@: Autocreator must be cleared before release, autocreator: %@",
//%         [self class], _autocreator);
//%  free(_context._values);
//%  [super dealloc];
//%}
//%- (BOOL)isEqual:(id)other {
//%  if (self == other) {
//%    return YES;
//%  }
//%  if (![other isKindOfClass:[GPB##LABEL##Array class]]) {
//%    return NO;
//%  }
//%  return GPBArrayHelper_isEqual(&_context,&((GPB##LABEL##Array *)other)->_context);
//%}
//%- (NSUInteger)hash {
//%  // Follow NSArray's lead, and use the count as the hash.
//%  return _context._count;
//%}
//%- (NSString *)description {
//%  return GPBArrayHelper_description(&_context,self,FORMAT);
//%}
//%- (void)enumerateValuesWithBlock:(void (^)(TYPE value, NSUInteger idx, BOOL *stop))block {
//%  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
//%}
//%- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
//%  usingBlock:(void (^)(TYPE value, NSUInteger idx, BOOL *stop))block {
//%  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
//%    TYPE temp;
//%    memcpy(&temp,value,sizeof(TYPE));
//%    block(temp,idx,stop);
//%  };
//%  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
//%}
//%- (TYPE)valueAtIndex:(NSUInteger)index {
//%   TYPE temp;
//%   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
//%  return temp;
//%}
//%- (void)addValue:(TYPE)value {
//%[self addValues:&value count:1];
//%}
//%- (void)addValues:(const TYPE [])values count:(NSUInteger)count {
//%  GPBArrayHelper_addValues(&_context,(char *)values,count);
//%  if (_autocreator) {
//%    GPBAutocreatedArrayModified(_autocreator, self);
//%  }
//%}
//%- (void)insertValue:(TYPE)value atIndex:(NSUInteger)index {
//%  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
//%  if (_autocreator) {
//%    GPBAutocreatedArrayModified(_autocreator, self);
//%  }
//%}
//%
//%- (void)replaceValueAtIndex:(NSUInteger)index withValue:(TYPE)value {
//%  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
//%}
//%- (void)addValuesFromArray:(GPB##LABEL##Array *)array {
//%  [self addValues:(TYPE *)array->_context._values count:array->_context._count];
//%}
//%- (void)removeValueAtIndex:(NSUInteger)index {
//%  GPBArrayHelper_removeValueAtIndex(&_context,index);
//%}
//%- (void)removeAll {
//%  GPBArrayHelper_removeAll(&_context);
//%}
//%- (void)exchangeValueAtIndex:(NSUInteger)idx1
//%  withValueAtIndex:(NSUInteger)idx2 {
//%    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
//%}
//%@end
//%


//%PDDM-EXPAND DEFINE_ARRAY(Int32,int32_t,int32_t,@"%d")
// This block of code is generated, do not edit it directly.

@implementation GPBInt32Array {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(int32_t)value {
  return [[(GPBInt32Array*)[self alloc] initWithValues:(int32_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBInt32Array *)array {
  return [[(GPBInt32Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(int32_t);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBInt32Array *)array {
  return [self initWithValues:(int32_t *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const int32_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBInt32Array allocWithZone:zone] initWithValues:(int32_t *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBInt32Array class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBInt32Array *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%d");
}
- (void)enumerateValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    int32_t temp;
    memcpy(&temp,value,sizeof(int32_t));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (int32_t)valueAtIndex:(NSUInteger)index {
   int32_t temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(int32_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const int32_t [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(int32_t)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int32_t)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBInt32Array *)array {
  [self addValues:(int32_t *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Bool,BOOL,char,@"%d")
// This block of code is generated, do not edit it directly.

@implementation GPBBoolArray {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(BOOL)value {
  return [[(GPBBoolArray*)[self alloc] initWithValues:(BOOL *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBBoolArray *)array {
  return [[(GPBBoolArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(BOOL);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBBoolArray *)array {
  return [self initWithValues:(BOOL *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const BOOL[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBBoolArray allocWithZone:zone] initWithValues:(BOOL *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBBoolArray class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBBoolArray *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%d");
}
- (void)enumerateValuesWithBlock:(void (^)(BOOL value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(BOOL value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    BOOL temp;
    memcpy(&temp,value,sizeof(BOOL));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (BOOL)valueAtIndex:(NSUInteger)index {
   BOOL temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(BOOL)value {
[self addValues:&value count:1];
}
- (void)addValues:(const BOOL [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(BOOL)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(BOOL)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBBoolArray *)array {
  [self addValues:(BOOL *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Double,double,double,@"%lf")
// This block of code is generated, do not edit it directly.

@implementation GPBDoubleArray {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(double)value {
  return [[(GPBDoubleArray*)[self alloc] initWithValues:(double *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBDoubleArray *)array {
  return [[(GPBDoubleArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(double);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBDoubleArray *)array {
  return [self initWithValues:(double *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const double[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBDoubleArray allocWithZone:zone] initWithValues:(double *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBDoubleArray class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBDoubleArray *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%lf");
}
- (void)enumerateValuesWithBlock:(void (^)(double value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(double value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    double temp;
    memcpy(&temp,value,sizeof(double));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (double)valueAtIndex:(NSUInteger)index {
   double temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(double)value {
[self addValues:&value count:1];
}
- (void)addValues:(const double [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(double)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(double)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBDoubleArray *)array {
  [self addValues:(double *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Float,float,float,@"%f")
// This block of code is generated, do not edit it directly.

@implementation GPBFloatArray {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(float)value {
  return [[(GPBFloatArray*)[self alloc] initWithValues:(float *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBFloatArray *)array {
  return [[(GPBFloatArray*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(float);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBFloatArray *)array {
  return [self initWithValues:(float *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const float[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBFloatArray allocWithZone:zone] initWithValues:(float *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBFloatArray class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBFloatArray *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%f");
}
- (void)enumerateValuesWithBlock:(void (^)(float value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(float value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    float temp;
    memcpy(&temp,value,sizeof(float));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (float)valueAtIndex:(NSUInteger)index {
   float temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(float)value {
[self addValues:&value count:1];
}
- (void)addValues:(const float [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(float)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(float)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBFloatArray *)array {
  [self addValues:(float *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(Int64,int64_t,int64_t,@"%lld")
// This block of code is generated, do not edit it directly.

@implementation GPBInt64Array {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(int64_t)value {
  return [[(GPBInt64Array*)[self alloc] initWithValues:(int64_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBInt64Array *)array {
  return [[(GPBInt64Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(int64_t);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBInt64Array *)array {
  return [self initWithValues:(int64_t *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const int64_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBInt64Array allocWithZone:zone] initWithValues:(int64_t *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBInt64Array class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBInt64Array *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%lld");
}
- (void)enumerateValuesWithBlock:(void (^)(int64_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(int64_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    int64_t temp;
    memcpy(&temp,value,sizeof(int64_t));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (int64_t)valueAtIndex:(NSUInteger)index {
   int64_t temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(int64_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const int64_t [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(int64_t)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int64_t)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBInt64Array *)array {
  [self addValues:(int64_t *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(UInt32,uint32_t,int32_t,@"%u")
// This block of code is generated, do not edit it directly.

@implementation GPBUInt32Array {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(uint32_t)value {
  return [[(GPBUInt32Array*)[self alloc] initWithValues:(uint32_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBUInt32Array *)array {
  return [[(GPBUInt32Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(uint32_t);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBUInt32Array *)array {
  return [self initWithValues:(uint32_t *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const uint32_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt32Array allocWithZone:zone] initWithValues:(uint32_t *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt32Array class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBUInt32Array *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%u");
}
- (void)enumerateValuesWithBlock:(void (^)(uint32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(uint32_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    uint32_t temp;
    memcpy(&temp,value,sizeof(uint32_t));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (uint32_t)valueAtIndex:(NSUInteger)index {
   uint32_t temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(uint32_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const uint32_t [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(uint32_t)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(uint32_t)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBUInt32Array *)array {
  [self addValues:(uint32_t *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND DEFINE_ARRAY(UInt64,uint64_t,int64_t,@"%llu")
// This block of code is generated, do not edit it directly.

@implementation GPBUInt64Array {
  @package
  GPBContext _context;
}
- (NSUInteger)count {
  return _context._count;
}
+ (instancetype)array {
  return [GPBArrayHelper_array(self) autorelease];
}
+ (instancetype)arrayWithValue:(uint64_t)value {
  return [[(GPBUInt64Array*)[self alloc] initWithValues:(uint64_t *)&value count:1] autorelease];
}
+ (instancetype)arrayWithValueArray:(GPBUInt64Array *)array {
  return [[(GPBUInt64Array*)[self alloc] initWithValueArray:array] autorelease];
}
+ (instancetype)arrayWithCapacity:(NSUInteger)count {
  return [[[self alloc] initWithCapacity:count] autorelease];
}
- (instancetype)init {
  self = [super init];
  if (self) {
     _context._valueSize = sizeof(uint64_t);
  }
  return self;
}
- (instancetype)initWithValueArray:(GPBUInt64Array *)array {
  return [self initWithValues:(uint64_t *)array->_context._values count:array->_context._count];
}
- (instancetype)initWithValues:(const uint64_t[])values count:(NSUInteger)count {
  self = [self init];
  if (self) {
    GPBArrayHelper_initWithValues(&_context,self,(char *)values,count);
  }
  return self;
}
- (instancetype)initWithCapacity:(NSUInteger)count {
  self = [self initWithValues:NULL count:0];
  if (self && count) {
  GPBArrayHelper_internalResizeToCapacity(&_context,count);
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBUInt64Array allocWithZone:zone] initWithValues:(uint64_t *)self->_context._values count:self->_context._count];
}
- (void)dealloc {
  NSAssert2(!_autocreator,
         @"%@: Autocreator must be cleared before release, autocreator: %@",
         [self class], _autocreator);
  free(_context._values);
  [super dealloc];
}
- (BOOL)isEqual:(id)other {
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBUInt64Array class]]) {
    return NO;
  }
  return GPBArrayHelper_isEqual(&_context,&((GPBUInt64Array *)other)->_context);
}
- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
  return _context._count;
}
- (NSString *)description {
  return GPBArrayHelper_description(&_context,self,@"%llu");
}
- (void)enumerateValuesWithBlock:(void (^)(uint64_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}
- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
  usingBlock:(void (^)(uint64_t value, NSUInteger idx, BOOL *stop))block {
  void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
    uint64_t temp;
    memcpy(&temp,value,sizeof(uint64_t));
    block(temp,idx,stop);
  };
  GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}
- (uint64_t)valueAtIndex:(NSUInteger)index {
   uint64_t temp;
   GPBArrayHelper_valueAtIndex(&_context,index,(char *)&temp);
  return temp;
}
- (void)addValue:(uint64_t)value {
[self addValues:&value count:1];
}
- (void)addValues:(const uint64_t [])values count:(NSUInteger)count {
  GPBArrayHelper_addValues(&_context,(char *)values,count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}
- (void)insertValue:(uint64_t)value atIndex:(NSUInteger)index {
  GPBArrayHelper_insertValue(&_context,(char *)&value,index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(uint64_t)value {
  GPBArrayHelper_replaceValueAtIndex(&_context,index,(char *)&value);
}
- (void)addValuesFromArray:(GPBUInt64Array *)array {
  [self addValues:(uint64_t *)array->_context._values count:array->_context._count];
}
- (void)removeValueAtIndex:(NSUInteger)index {
  GPBArrayHelper_removeValueAtIndex(&_context,index);
}
- (void)removeAll {
  GPBArrayHelper_removeAll(&_context);
}
- (void)exchangeValueAtIndex:(NSUInteger)idx1
  withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1,idx2);
}
@end

//%PDDM-EXPAND-END (7 expansions)



#pragma mark - NSArray Subclass

@implementation GPBAutocreatedArray {
  NSMutableArray *_array;
}

- (void)dealloc {
  NSAssert2(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
  [_array release];
  [super dealloc];
}

#pragma mark Required NSArray overrides

- (NSUInteger)count {
  return [_array count];
}

- (id)objectAtIndex:(NSUInteger)idx {
  return [_array objectAtIndex:idx];
}

#pragma mark Required NSMutableArray overrides

// Only need to call GPBAutocreatedArrayModified() when adding things since
// we only autocreate empty arrays.

- (void)insertObject:(id)anObject atIndex:(NSUInteger)idx {
  if (_array == nil) {
    _array = [[NSMutableArray alloc] init];
  }
  [_array insertObject:anObject atIndex:idx];
  
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)removeObject:(id)anObject {
  [_array removeObject:anObject];
}

- (void)removeObjectAtIndex:(NSUInteger)idx {
  [_array removeObjectAtIndex:idx];
}

- (void)addObject:(id)anObject {
  if (_array == nil) {
    _array = [[NSMutableArray alloc] init];
  }
  [_array addObject:anObject];
  
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)removeLastObject {
  [_array removeLastObject];
}

- (void)replaceObjectAtIndex:(NSUInteger)idx withObject:(id)anObject {
  [_array replaceObjectAtIndex:idx withObject:anObject];
}

#pragma mark Extra things hooked

- (id)copyWithZone:(NSZone *)zone {
  if (_array == nil) {
    return [[NSMutableArray allocWithZone:zone] init];
  }
  return [_array copyWithZone:zone];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
  if (_array == nil) {
    return [[NSMutableArray allocWithZone:zone] init];
  }
  return [_array mutableCopyWithZone:zone];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])buffer
                                    count:(NSUInteger)len {
  return [_array countByEnumeratingWithState:state objects:buffer count:len];
}

- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
  [_array enumerateObjectsUsingBlock:block];
}

- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts
                         usingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block {
  [_array enumerateObjectsWithOptions:opts usingBlock:block];
}

@end


#pragma mark - Enum

@implementation GPBEnumArray {
  @package
  GPBContext _context;
  GPBEnumValidationFunc _validationFunc;
}

@synthesize validationFunc = _validationFunc;

- (NSUInteger)count {
    return _context._count;
}

+ (instancetype)array {
  return [[[self alloc] initWithValidationFunction:NULL] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func {
  return [[[self alloc] initWithValidationFunction:func] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func
                                   rawValue:(int32_t)value {
  return [[[self alloc] initWithValidationFunction:func
                                         rawValues:&value
                                             count:1] autorelease];
}

+ (instancetype)arrayWithValueArray:(GPBEnumArray *)array {
  return [[(GPBEnumArray*)[self alloc] initWithValueArray:array] autorelease];
}

+ (instancetype)arrayWithValidationFunction:(GPBEnumValidationFunc)func
                                   capacity:(NSUInteger)count {
  return [[[self alloc] initWithValidationFunction:func capacity:count] autorelease];
}

- (instancetype)init {
  return [self initWithValidationFunction:NULL];
}

- (instancetype)initWithValueArray:(GPBEnumArray *)array {
  return [self initWithValidationFunction:array->_validationFunc
                                rawValues:(int32_t *)array->_context._values
                                    count:array->_context._count];
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func {
  self = [super init];
  if (self) {
      _context._valueSize = sizeof(int32_t);
    _validationFunc = (func != NULL ? func : ArrayDefault_IsValidValue);
  }
  return self;
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                 rawValues:(const int32_t [])values
                                     count:(NSUInteger)count {
  self = [self initWithValidationFunction:func];
  if (self) {
      GPBArrayHelper_initWithValues(&_context,self, (char *)values, count);
  }
  return self;
}

- (instancetype)initWithValidationFunction:(GPBEnumValidationFunc)func
                                  capacity:(NSUInteger)count {
  self = [self initWithValidationFunction:func];
  if (self && count) {
    [self internalResizeToCapacity:count];
  }
  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone {
  return [[GPBEnumArray allocWithZone:zone]
          initWithValidationFunction:_validationFunc
          rawValues:(int32_t *)_context._values
          count:_context._count];
}


- (void)dealloc {
  NSAssert2(!_autocreator,
           @"%@: Autocreator must be cleared before release, autocreator: %@",
           [self class], _autocreator);
    free(_context._values);
  [super dealloc];
}

- (BOOL)isEqual:(id)other {
    
  if (self == other) {
    return YES;
  }
  if (![other isKindOfClass:[GPBEnumArray class]]) {
    return NO;
  }
    return GPBArrayHelper_isEqual(&_context,&((GPBEnumArray *)other)->_context);
}

- (NSUInteger)hash {
  // Follow NSArray's lead, and use the count as the hash.
    return _context._count;
}

- (NSString *)description {
    return GPBArrayHelper_description(&_context,self,@"%d");
}

- (void)enumerateRawValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateRawValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}

- (void)enumerateRawValuesWithOptions:(NSEnumerationOptions)opts
                           usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
    void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
        int32_t temp;
        memcpy(&temp,value,sizeof(int32_t));
        block(temp,idx,stop);
    };
   GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}

- (int32_t)valueAtIndex:(NSUInteger)index {
    int32_t result;
    GPBArrayHelper_valueAtIndex(&_context,index, (char *)&result);
  if (!_validationFunc(result)) {
    result = kGPBUnrecognizedEnumeratorValue;
  }
  return result;
}

- (int32_t)rawValueAtIndex:(NSUInteger)index {
    int32_t result;
    GPBArrayHelper_valueAtIndex(&_context, index, (char *)&result);

    return result;
}

- (void)enumerateValuesWithBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  [self enumerateValuesWithOptions:(NSEnumerationOptions)0 usingBlock:block];
}

- (void)enumerateValuesWithOptions:(NSEnumerationOptions)opts
                        usingBlock:(void (^)(int32_t value, NSUInteger idx, BOOL *stop))block {
  // NSEnumerationConcurrent isn't currently supported (and Apple's docs say that is ok).
    void (^block2)(const char *value, NSUInteger idx, BOOL *stop) = ^(const char * value, NSUInteger idx, BOOL *stop) {
        int32_t temp;
        memcpy(&temp,value,sizeof(temp));
        if (!_validationFunc(temp)) {
            temp = kGPBUnrecognizedEnumeratorValue;
        }
        block(temp,idx,stop);
    };
    GPBArrayHelper_enumerateValuesWithOptions(&_context,opts,block2);
}


- (void)internalResizeToCapacity:(NSUInteger)newCapacity {
    GPBArrayHelper_internalResizeToCapacity(&_context,newCapacity);
}

- (void)addRawValue:(int32_t)value {
  [self addRawValues:&value count:1];
}

- (void)addRawValues:(const int32_t [])values count:(NSUInteger)count {
    GPBArrayHelper_addValues(&_context,(char *)values, count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)insertRawValue:(int32_t)value atIndex:(NSUInteger)index {
    GPBArrayHelper_insertValue(&_context,(char *)&value, index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withRawValue:(int32_t)value {
    GPBArrayHelper_replaceValueAtIndex(&_context,index, (char *)&value);
}

- (void)addRawValuesFromArray:(GPBEnumArray *)array {
  [self addRawValues:(int32_t *)array->_context._values count:array->_context._count];
}

- (void)removeValueAtIndex:(NSUInteger)index {
    GPBArrayHelper_removeValueAtIndex(&_context,index);
}

- (void)removeAll {
    GPBArrayHelper_removeAll(&_context);
}

- (void)exchangeValueAtIndex:(NSUInteger)idx1
            withValueAtIndex:(NSUInteger)idx2 {
    GPBArrayHelper_exchangeValueAtIndex(&_context,idx1, idx2);
}

- (void)addValue:(int32_t)value {
  [self addValues:&value count:1];
}

- (void)addValues:(const int32_t [])values count:(NSUInteger)count {
  if (values == NULL || count == 0) return;
  GPBEnumValidationFunc func = _validationFunc;
  for (NSUInteger i = 0; i < count; ++i) {
    if (!func(values[i])) {
      [NSException raise:NSInvalidArgumentException
                  format:@"%@: Attempt to set an unknown enum value (%d)",
       [self class], values[i]];
    }
  }
    GPBArrayHelper_addValues(&_context,(char *)values, count);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)insertValue:(int32_t)value atIndex:(NSUInteger)index {

  if (!_validationFunc(value)) {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Attempt to set an unknown enum value (%d)",
     [self class], value];
  }
    GPBArrayHelper_insertValue(&_context,(char *)&value, index);
  if (_autocreator) {
    GPBAutocreatedArrayModified(_autocreator, self);
  }
}

- (void)replaceValueAtIndex:(NSUInteger)index withValue:(int32_t)value {

  if (!_validationFunc(value)) {
    [NSException raise:NSInvalidArgumentException
                format:@"%@: Attempt to set an unknown enum value (%d)",
     [self class], value];
  }
    GPBArrayHelper_replaceValueAtIndex(&_context, index, (char *)&value);
}
@end


#pragma clang diagnostic pop
