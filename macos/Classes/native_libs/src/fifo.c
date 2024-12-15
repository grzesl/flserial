#include "../include/fifo.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// This initializes the FIFO structure with the given buffer and size
fifo_t *fifo_create(int size) {
  fifo_t *f = (fifo_t *)malloc(sizeof(fifo_t));
  if (f == NULL) {
    fprintf(stderr, "fifo_create: out of memory\n");
    return NULL;
  }
  f->head = 0;
  f->tail = 0;
  f->size = size + 1;
  f->data = (fifo_payload_t *)malloc((size + 1) * sizeof(fifo_payload_t));
  if (f->data == NULL) {
    fprintf(stderr, "fifo_create: out of memory\n");
    return NULL;
  }
  return f;
}

// release the fifo memory
void fifo_destroy(fifo_t *f) {
  if (f->data != NULL) {
    free(f->data);
  }
  if (f != NULL) {
    free(f);
  }
}

// This reads ndata payloads from the FIFO
// The number of payloads read is returned
int fifo_read(fifo_t *f, fifo_payload_t *data, int ndata) {
  int i;
  fifo_payload_t *p = data;
  for (i = 0; i < ndata; i++) {
    if (f->tail != f->head) {   // see if any data is available
      *p++ = f->data[f->tail];  // grab a payload from the buffer
      f->tail++;                // increment the tail
      if (f->tail == f->size) { // check for wrap-around
        f->tail = 0;
      }
    } else {
      return i; // number of payloads read
    }
  }
  return ndata;
}

// This writes up to ndata payloads to the FIFO
// If the head runs in to the tail, not all payloads are written
// The number of payloads written is returned
int fifo_write(fifo_t *f, const fifo_payload_t *data, int ndata) {
  int i;
  const fifo_payload_t *p;
  p = data;
  for (i = 0; i < ndata; i++) {
    // first check to see if there is space in the buffer
    if ((f->head + 1 == f->tail) ||
        ((f->head + 1 == f->size) && (f->tail == 0))) {
      return i; // no more room
    } else {
      f->data[f->head] = *p++;
      f->head++;                // increment the head
      if (f->head == f->size) { // check for wrap-around
        f->head = 0;
      }
    }
  }
  return ndata;
}

// returns true if the FIFO has data available
int fifo_data_available(fifo_t *f) {
    return(f->tail != f->head);
}

// clears all entries in the FIFO
void fifo_clear(fifo_t *f) {
    f->tail = f->head = 0;
}
