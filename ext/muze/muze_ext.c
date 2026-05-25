#include "ruby.h"

static VALUE mMuze;
static VALUE mNative;

static VALUE muze_parameter_error(void) {
  ID id = rb_intern("ParameterError");
  if (rb_const_defined(mMuze, id)) {
    return rb_const_get(mMuze, id);
  }

  return rb_eArgError;
}

static VALUE native_frame_slices(VALUE self, VALUE rb_signal, VALUE rb_frame_length, VALUE rb_hop_length) {
  if (!RB_TYPE_P(rb_signal, T_ARRAY)) {
    rb_raise(muze_parameter_error(), "signal must be an Array");
  }

  const long signal_length = RARRAY_LEN(rb_signal);
  const long frame_length = NUM2LONG(rb_frame_length);
  const long hop_length = NUM2LONG(rb_hop_length);

  if (frame_length <= 0 || hop_length <= 0) {
    rb_raise(muze_parameter_error(), "frame_length and hop_length must be positive");
  }

  if (signal_length <= frame_length) {
    VALUE frame = rb_ary_new2(frame_length);
    for (long i = 0; i < frame_length; i++) {
      VALUE sample = i < signal_length ? rb_ary_entry(rb_signal, i) : DBL2NUM(0.0);
      rb_ary_push(frame, sample);
    }
    VALUE single = rb_ary_new();
    rb_ary_push(single, frame);
    return single;
  }

  const long frame_count = ((signal_length - frame_length) / hop_length) + 1;
  VALUE frames = rb_ary_new2(frame_count);

  for (long frame_idx = 0; frame_idx < frame_count; frame_idx++) {
    long start = frame_idx * hop_length;
    VALUE frame = rb_ary_new2(frame_length);

    for (long i = 0; i < frame_length; i++) {
      rb_ary_push(frame, rb_ary_entry(rb_signal, start + i));
    }

    rb_ary_push(frames, frame);
  }

  return frames;
}

static void swap_double(double *values, long left, long right) {
  const double tmp = values[left];
  values[left] = values[right];
  values[right] = tmp;
}

static long partition_double(double *values, long left, long right, long pivot_index) {
  const double pivot = values[pivot_index];
  long store_index = left;

  swap_double(values, pivot_index, right);

  for (long i = left; i < right; i++) {
    if (values[i] < pivot) {
      swap_double(values, store_index, i);
      store_index++;
    }
  }

  swap_double(values, right, store_index);
  return store_index;
}

static double quickselect_double(double *values, long count, long target) {
  long left = 0;
  long right = count - 1;

  while (1) {
    if (left == right) return values[left];

    const long pivot_index = partition_double(values, left, right, left + ((right - left) / 2));

    if (target == pivot_index) {
      return values[target];
    } else if (target < pivot_index) {
      right = pivot_index - 1;
    } else {
      left = pivot_index + 1;
    }
  }
}

static VALUE native_median1d(VALUE self, VALUE rb_values) {
  if (!RB_TYPE_P(rb_values, T_ARRAY)) {
    rb_raise(muze_parameter_error(), "values must be an Array");
  }

  const long count = RARRAY_LEN(rb_values);
  if (count == 0) return DBL2NUM(0.0);

  double *values = ALLOC_N(double, count);

  for (long i = 0; i < count; i++) {
    values[i] = NUM2DBL(rb_ary_entry(rb_values, i));
  }

  const double median = quickselect_double(values, count, count / 2);
  xfree(values);
  return DBL2NUM(median);
}

void Init_muze_ext(void) {
  mMuze = rb_define_module("Muze");
  mNative = rb_define_module_under(mMuze, "Native");

  rb_define_singleton_method(mNative, "frame_slices", native_frame_slices, 3);
  rb_define_singleton_method(mNative, "median1d", native_median1d, 1);
}
