#include <stdio.h>
#include <string.h>
#include <time.h>
#include "ruby.h"
#include "emulsion.h"

typedef struct EmulsionStruct {
  VALUE stringRefs[100];
  int stringRefsTop;

  VALUE objectRefs[100];
  int objectRefsTop;
} EmulsionParser;

#define EVIL 0x666
static VALUE cEmulsion;

static char *parseAmf(EmulsionParser *emulsionParser, char *p, char *pe, VALUE *value);

%%{
  machine amf_common;

  U29_1 = 0x00..0x7f;
  U29_2 = 0x80..0xff 0x00..0x7f;
  U29_3 = 0x80..0xff 0x80..0xff 0x00..0x7f;
  U29_4 = 0x80..0xff 0x80..0xff 0x80..0xff 0xff..0x00;
  U29 = U29_1 | U29_2 | U29_3 | U29_4;
  UTF8_1 = 0x00..0x7f;
  UTF8_tail = 0x80..0xbf;
  UTF8_2 = 0xc2..0xdf UTF8_tail;
  UTF8_3 = ( 0xe0 0xa0..0xbf UTF8_tail ) | ( 0xe1..0xec UTF8_tail{2} ) | ( 0xed 0x80..0x9f UTF8_tail ) | ( 0xee..0xef UTF8_tail{2} );
  UTF8_4 = ( 0xf0 0x90..0xbf UTF8_tail{2} ) | ( 0xf1..0xf3 UTF8_tail{3} ) | ( 0xf4 0x80..0x8f UTF8_tail{2} );
  UTF8_char = UTF8_1 | UTF8_2 | UTF8_3 | UTF8_4;
  U29S_ref = U29;
  U29S_value = U29;
  U29A_value = U29;
  UTF_8_empty = 0x01;
  UTF_8_vr = U29S_ref | ( U29S_value UTF8_char* );
  undefined_marker = "\0";
  null_marker = 0x01;
  false_marker = 0x02;
  true_marker = 0x03;
  integer_marker = 0x04;
  double_marker = 0x05;
  string_marker = 0x06;
  xml_doc_marker = 0x07;
  date_marker = "\b";
  array_marker = 0x09;
  object_marker = 0x0A;
  xml_marker = 0x0B;
  byte_array_marker = "\f";
  undefined_type = undefined_marker;
  string_type = string_marker UTF_8_vr;
  integer_type = integer_marker U29;
  U29O_traits = U29;
  class_name =  UTF_8_vr;
  value_type = undefined_marker | null_marker | false_marker | true_marker | integer_type | double_marker | string_type | xml_doc_marker | date_marker | array_marker | object_marker | xml_marker | byte_array_marker;
}%%

static char *parseInteger(char *p, unsigned long *result) {
  int n = 0;
  unsigned char b = 0;
  b = *p;

  while((b & 0x80) != 0 && n < 3) {
    *result = *result << 7;
    *result = *result | (b & 0x7f);
    ++p;
    b = *p;
    ++n;
  }

  if (n < 3) {
    *result = *result<< 7;
    *result = *result| b;
  }
  else {
    //Use all 8 bits from the 4th byte
    *result = *result << 8;
    *result = *result | b;
    //Check if the integer should be negative
    if (*result > 268435455) {
      *result -= (1 << 29);
    }
  }

  //Increment the pointet to point to the next characer to process
  if(n == 0) {
    ++p;
  }
  return p;
}

static char *parseDouble(char *p, double *result) {

  union doubleOrByte {
    char buffer[sizeof(double)];
    double val;
  } converter;

  int i = 0;

  for(i = 7; i >= 0; i--) {
    converter.buffer[i] = *p;
    ++p;
  }

  *result = converter.val;
  return p;
}


%%{
  machine amf_string;
  write data;
  include amf_common;

  action parse_length {
    if(*fpc & 0x01 == 1) {
      np = parseInteger(fpc, &length);
      length = length >> 1;
      if(length == 0) {
        *result = rb_str_new("",0);
        fexec np;
        fbreak;
      }
      else {
        fexec np;
      }
    }
    else {
      *fpc = *fpc >> 1;
      unsigned long stringIndex = 0;
      np = parseInteger(fpc, &stringIndex);
      *result = emulsionParser->stringRefs[stringIndex];
      fexec np;
      fbreak;
    }
  }

  action parse_string {
   *result = rb_str_new(fpc, length);
   emulsionParser->stringRefs[emulsionParser->stringRefsTop] = *result;
   emulsionParser->stringRefsTop++;
  }

main:= U29S_value >parse_length (UTF8_char+ >parse_string);
}%%
static char *parseString(EmulsionParser *emulsionParser, char *p, char *pe, VALUE *result) {
  int cs = EVIL;
  unsigned long length = 0;
  char *np;

  %% write init;
  %% write exec;

  return np+length;
}

static char *parseDate(EmulsionParser *emulsionParser, char *p, VALUE *result) {

  if(*p & 0x01 == 1) {
    p++;

    union timeOrByte {
      char buffer[8];
      time_t val;
    } converter;

    int i = 0;
    for(i = 7; i >= 0; i--) {
      converter.buffer[i] = *p;
      ++p;
    }

    *result = rb_time_new(0, converter.val);
    emulsionParser->objectRefs[emulsionParser->objectRefsTop] = *result;
    emulsionParser->objectRefsTop++;
  }
  else {
    unsigned long objectIndex = 0;
    *p = *p >> 1;
    p = parseInteger(p, &objectIndex);
    *result = emulsionParser->objectRefs[objectIndex];
  }

  return p;
}

static char *parseXml(EmulsionParser *emulsionParser, char *p, VALUE *result) {
  char *np;
  if(*p & 0x01 == 1) {
    unsigned long length = 0;
    *p = *p >> 1;
    np = parseInteger(p, &length);
    *result = rb_str_new(np, length);
    emulsionParser->objectRefs[emulsionParser->objectRefsTop] = *result;
    emulsionParser->objectRefsTop++;
    np = np+length;
    return np;
  }
  else {
    unsigned long objectIndex = 0;
    *p = *p >> 1;
    np = parseInteger(p, &objectIndex);
    *result = emulsionParser->objectRefs[objectIndex];
    return np;
  }
}

%%{
  machine amf_object;
  write data;
  include amf_common;

  action parseDynamic {

    if(*fpc & 0x01 == 1) {
      unsigned long flag;
      char *np = parseInteger(fpc, &flag);
      isDynamic = (flag & 0x08) != 0 ? 1 : 0;
      fexec np;
    }
    else {
      unsigned long objectIndex = 0;
      *fpc = *fpc >> 1;
      np = parseInteger(fpc, &objectIndex);
      *value = emulsionParser->objectRefs[objectIndex];
      fexec np;
      fbreak;
    }
  }

  action parseClassName {
    if(*fpc == 0x01) {
      *value = rb_hash_new();
      fpc = fpc+1;
      fexec fpc;
    }
    else {
      isConcrete = 1;
      char *np = parseString(emulsionParser, fpc, pe, &className);

      VALUE class = rb_funcall(cEmulsion, classForId, 1, className);

      if(class == Qnil) {
        ID class_id = rb_intern(StringValuePtr(className));
        class = rb_const_get(rb_cObject, class_id);
      }

      VALUE argv[0];
      *value = rb_class_new_instance(0, argv, class);
      fexec np;
    }
    emulsionParser->objectRefs[emulsionParser->objectRefsTop] = *value;
    emulsionParser->objectRefsTop++;
  }

  action parseMemberName {
    if(*fpc == 0x01) {
      np = fpc+1;
      fexec np;
      fbreak;
    }
    else if(*fpc & 0x01 == 1) {
      char *np = parseString(emulsionParser, fpc, pe, &memberName);
      fexec np;
      fnext v_type;
    }
    else {
      unsigned long stringMemberIndex = 0;
      *fpc = *fpc >> 1;
      np = parseInteger(fpc, &stringMemberIndex);
      memberName = emulsionParser->stringRefs[stringMemberIndex];
      fexec np;
      fnext v_type;
    }
  }

  action parseType {
    char *np = parseAmf(emulsionParser, fpc, pe, &memberValue);
    if(isConcrete) {
      unsigned long memberNameLen = RSTRING(memberName)->len;
      char instance_var_name[memberNameLen + 1];
      instance_var_name[0] = '\0';
      strncat(instance_var_name, "@", 1);
      strncat(instance_var_name, RSTRING(memberName)->ptr, memberNameLen);
      rb_iv_set(*value, instance_var_name, memberValue);
    }
    else {
      rb_hash_aset(*value, rb_str_intern(memberName), memberValue);
    }

    fexec np;
    fnext member;
  }

  member := (U29S_value)>parseMemberName;
  v_type := value_type >parseType;
  object:= U29O_traits >parseDynamic class_name >parseClassName (U29S_value)> {fhold; fgoto member;};
}%%

static char *parseObject(EmulsionParser *emulsionParser, char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  char *np;
  VALUE className = Qnil;
  unsigned char isDynamic;
  unsigned char isConcrete = 0;
  VALUE memberName = Qnil;
  VALUE memberValue = Qnil;
  ID classForId = rb_intern("class_for");
  %% write init;
  %% write exec;
  return np;
}


%%{
  machine amf_array;
  write data;
  include amf_common;

  action parseDensePortion {
    if(*fpc & 0x01 == 1) {
      *fpc = *fpc >> 1;
      np = parseInteger(fpc, &denseLength);
    }
    else {
      unsigned long arrayIndex = 0;
      *fpc = *fpc >> 1;
      np = parseInteger(fpc, &arrayIndex);
      *value = emulsionParser->objectRefs[arrayIndex];
      fexec np;
      fbreak;
    }
    fexec np;
  }

  action parseEmptyArray {
    //TODO Optimize this so we initialize the ruby array with the parsed values
    *value = rb_ary_new();
    emulsionParser->objectRefs[emulsionParser->objectRefsTop] = *value;
    emulsionParser->objectRefsTop++;

    if(denseLength == 0) {
      fbreak;
    }
  }

  action parseType {
    unsigned long i = 0;
    for(i=0; i < denseLength; i++) {
      fpc = parseAmf(emulsionParser, fpc, pe, &element);
      rb_ary_push(*value, element);
    }
    fexec fpc;
    fbreak;
  }

  main := U29A_value >parseDensePortion (UTF_8_empty >parseEmptyArray) value_type >parseType;
}%%

static char *parseArray(EmulsionParser *emulsionParser, char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  const char *eof = 0;
  char *np;
  unsigned long denseLength = 0;
  VALUE *elements;
  VALUE element;
  %% write init;
  %% write exec;
  return p;
}

%%{
  machine amf;
  write data;
  include amf_common;

  action parse_null {
    *value = Qnil;
    np = fpc+1;
    fbreak;
  }

  action parse_false {
    *value = Qfalse;
    np = fpc+1;
    fbreak;
  }

  action parse_true {
    *value = Qtrue;
    np = fpc+1;
    fbreak;
  }

  action parse_integer {
    fpc++;
    unsigned long intValue = 0;
    np = parseInteger(fpc, &intValue);
    *value = INT2NUM(intValue);
    fbreak;
  }

  action parse_double {
    fpc++;
    double doubleValue = 0.0;
    np = parseDouble(fpc, &doubleValue);
    *value = INT2NUM(doubleValue);
    fbreak;
  }

  action parse_date {
    fpc++;
    np = parseDate(emulsionParser, fpc, value);
    fbreak;
  }

  action parse_xml {
    fpc++;
    np = parseXml(emulsionParser, fpc, value);
    fbreak;
  }

  action parse_string {
    fpc++;
    np = parseString(emulsionParser, fpc, pe, value);
    fbreak;
  }

  action parse_object {
    fpc++;
    np = parseObject(emulsionParser, fpc, pe, value);
    fbreak;
  }

  action parse_array {
    fpc++;
    np = parseArray(emulsionParser, fpc, pe, value);
    fbreak;
  }

  action exit {
    //fhold; fbreak;
  }

  main := ( null_marker>parse_null |
            string_type> parse_string |
            false_marker>parse_false |
            true_marker>parse_true |
            integer_marker >parse_integer |
            double_marker>parse_double |
            date_marker>parse_date |
            xml_doc_marker>parse_xml |
            xml_marker>parse_xml |
            object_marker >parse_object |
            array_marker >parse_array)%*exit;

}%%
static char *parseAmf(EmulsionParser *emulsionParser, char *p, char *pe, VALUE *value) {
  int cs = EVIL;
  char *np;

  %% write init;
  %% write exec;

  return np;
}


static VALUE cEmulsion_initialize(VALUE self) {
  EmulsionParser *emulsionParser;
  Data_Get_Struct(self, EmulsionParser, emulsionParser);
  emulsionParser->objectRefsTop = 0;
  emulsionParser->objectRefsTop = 0;
}

static VALUE parse(VALUE self, VALUE amf) {
  EmulsionParser *emulsionParser;
  Data_Get_Struct(self, EmulsionParser, emulsionParser);

  VALUE source = StringValue(amf);
  VALUE value = Qnil;
  long len = RSTRING(source)->len;
  char *p = RSTRING(source)->ptr;
  char *pe = p + len;
  parseAmf(emulsionParser, p, pe, &value);
  return value;
}

static EmulsionParser *emulsionAllocate()
{
    EmulsionParser *emulsionParser = ALLOC(EmulsionParser);
    MEMZERO(emulsionParser, EmulsionParser, 1);
    return emulsionParser;
}

static void emulsionMark(EmulsionParser *emulsionParser)
{
  //TODO Mark ruby objects stored in reference arrays
  //rb_gc_mark_maybe(emulsionParser->stringRefs);
  //rb_gc_mark_maybe(emulsionParser->objectRefs);
}

static void emulsionFree(EmulsionParser *emulsionParser)
{
    ruby_xfree(emulsionParser);
}

static VALUE cEmulsion_allocate(VALUE klass) {
  EmulsionParser *emulsionParser = emulsionAllocate();
  return Data_Wrap_Struct(klass, emulsionMark, emulsionFree, emulsionParser);
}

void Init_emulsion()
{
  cEmulsion = rb_define_class("Emulsion", rb_cObject);
  rb_define_alloc_func(cEmulsion, cEmulsion_allocate);
  rb_define_method(cEmulsion, "initialize", cEmulsion_initialize, 0);
  rb_define_method(cEmulsion, "parse", parse, 1);
}
