#include "ruby.h"
#include "ruby/thread.h"
#include <string.h>

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

struct median_args {
  double *values;
  long count;
  long target;
  double result;
};

static void *median_without_gvl(void *ptr) {
  struct median_args *args = (struct median_args *)ptr;
  args->result = quickselect_double(args->values, args->count, args->target);
  return NULL;
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

  struct median_args args = { values, count, count / 2, 0.0 };
  rb_thread_call_without_gvl(median_without_gvl, &args, NULL, NULL);
  xfree(values);
  return DBL2NUM(args.result);
}

static void insert_sorted_double(double *values, long *length, double value) {
  long index = 0;
  while (index < *length && values[index] <= value) index++;
  memmove(values + index + 1, values + index, sizeof(double) * (*length - index));
  values[index] = value;
  (*length)++;
}

static void remove_sorted_double(double *values, long *length, double value) {
  long index = 0;
  while (index < *length && values[index] < value) index++;
  while (index < *length && values[index] != value) index++;
  if (index >= *length) return;

  memmove(values + index, values + index + 1, sizeof(double) * (*length - index - 1));
  (*length)--;
}

static VALUE native_median_filter1d(VALUE self, VALUE rb_values, VALUE rb_half) {
  if (!RB_TYPE_P(rb_values, T_ARRAY)) {
    rb_raise(muze_parameter_error(), "values must be an Array");
  }

  const long count = RARRAY_LEN(rb_values);
  const long half = NUM2LONG(rb_half);
  if (half < 0) {
    rb_raise(muze_parameter_error(), "half must be non-negative");
  }

  VALUE output = rb_ary_new2(count);
  if (count == 0) return output;

  double *window = ALLOC_N(double, count);
  long window_length = 0;

  for (long index = 0; index < count; index++) {
    if (index > half) {
      remove_sorted_double(window, &window_length, NUM2DBL(rb_ary_entry(rb_values, index - half - 1)));
    }

    const long entering = index + half;
    if (entering < count) {
      insert_sorted_double(window, &window_length, NUM2DBL(rb_ary_entry(rb_values, entering)));
    }

    rb_ary_push(output, DBL2NUM(window_length == 0 ? 0.0 : window[window_length / 2]));
  }

  xfree(window);
  return output;
}

void Init_muze_ext(void) {
  mMuze = rb_define_module("Muze");
  mNative = rb_define_module_under(mMuze, "Native");

  rb_define_singleton_method(mNative, "frame_slices", native_frame_slices, 3);
  rb_define_singleton_method(mNative, "median1d", native_median1d, 1);
  rb_define_singleton_method(mNative, "median_filter1d", native_median_filter1d, 2);
}
