#include <stdio.h>
#include <string.h>
#include <time.h>
#include "ruby.h"
#include "emulsion.h"


#define EVIL 0x666
static VALUE parse_string(char *p, char *pe);
static VALUE parse(VALUE self, VALUE amf);
static VALUE cEmulsion;

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
  array_marker = "\t";
  object_marker = 0x0A;
  xml_marker = 0x0B;
  byte_array_marker = "\f";
  undefined_type = undefined_marker;
  string_type = string_marker UTF_8_vr;
  integer_type = integer_marker U29;
}%%

%%{
  machine amf_string;
  write data;
  include amf_common;

main:= (U29S_ref | U29S_value (UTF8_char*)${ rb_str_cat( result, p, 1 ); });
}%%
//TODO Fix string parser to not use sb_str_cat
static VALUE parse_string(char *p, char *pe) {
  VALUE result = rb_str_new("", 0);
  int cs = EVIL;
  %% write init;
  %% write exec;
  return result;
}

static VALUE parse_integer(char *p, char *pe) {
  ++p;
  int n = 0;
  unsigned char b = 0;
  unsigned long result = 0;
  b = *p;

  while((b & 0x80) != 0 && n < 3) {
    result = result << 7;
    result = result | (b & 0x7f);
    ++p;
    b = *p;
    ++n;
  }

  if (n < 3) {
    result = result << 7;
    result = result | b;
  }
  else {
    //Use all 8 bits from the 4th byte
    result = result << 8;
    result = result | b;
    //Check if the integer should be negative
    if (result > 268435455) {
      result -= (1 << 29);
    }
  }

  return INT2NUM(result);
}

static VALUE parse_double(char *p, char *pe) {
  p++;

  union doubleOrByte {
    char buffer[sizeof(double)];
    double val;
  } converter;

  int i = 0;

  for(i = 7; i >= 0; i--) {
    converter.buffer[i] = *p;
    ++p;
  }

  return INT2NUM(converter.val);
}

static VALUE parse_date(char *p, char *pe) {
  ++p;
  ++p;

  union doubleOrByte {
    char buffer[sizeof(time_t)];
    time_t val;
  } converter;

  int i = 0;

  for(i = 7; i >= 0; i--) {
    converter.buffer[i] = *p;
    ++p;
  }

  VALUE time = rb_time_new(0, converter.val);
  return time;
}

static VALUE parse_xml(char *p, char *pe) {
  ++p;
  unsigned long length = *p >> 1;
  ++p;

  return rb_str_new(p, length);
}

static VALUE parse_object(char *p, char *pe) {
}

%%{
  machine amf;
  write data;
  include amf_common;

  action parse_null {
    return Qnil;
  }

  action parse_string {
    return parse_string(fpc+1, pe);
  }

  action parse_false {
    return Qfalse;
  }

  action parse_true {
    return Qtrue;
  }

  action parse_integer {
    return parse_integer(fpc, pe);
  }

  action parse_double {
    return parse_double(fpc,pe);
  }

  action parse_date {
    return parse_date(fpc, pe);
  }

  action parse_xml {
    return parse_xml(fpc, pe);
  }

  action parse_object {
    return parse_object(fpc, pe);
  }

main := ( null_marker>parse_null |
          string_marker>parse_string |
          false_marker>parse_false |
          true_marker>parse_true |
          integer_marker>parse_integer |
          double_marker>parse_double |
          date_marker>parse_date |
          xml_doc_marker>parse_xml |
          xml_marker>parse_xml |
          object_marker>parse_object)*;

}%%
static VALUE parse(VALUE self, VALUE amf) {
  char *p, *pe;
  int cs = EVIL;
  VALUE result = Qnil;
  VALUE source = StringValue(amf);
  long len = RSTRING(source)->len;

  %% write init;
  p = RSTRING(source)->ptr;
  pe = p + len;
  %% write exec;
  return amf;
}

void Init_emulsion()
{
  cEmulsion = rb_define_class("Emulsion", rb_cObject);
  rb_define_method(cEmulsion, "parse", parse, 1);
}
