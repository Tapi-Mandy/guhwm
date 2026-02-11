const char *colorname[] = {

  /* 8 normal colors */
  [0] = "#4a3c33", /* black   */
  [1] = "#B19B8D", /* red     */
  [2] = "#BBA597", /* green   */
  [3] = "#C2AC9E", /* yellow  */
  [4] = "#CCB6A8", /* blue    */
  [5] = "#D9C5B6", /* magenta */
  [6] = "#E1CCBD", /* cyan    */
  [7] = "#e5deda", /* white   */

  /* 8 bright colors */
  [8]  = "#a09b98",  /* black   */
  [9]  = "#B19B8D",  /* red     */
  [10] = "#BBA597", /* green   */
  [11] = "#C2AC9E", /* yellow  */
  [12] = "#CCB6A8", /* blue    */
  [13] = "#D9C5B6", /* magenta */
  [14] = "#E1CCBD", /* cyan    */
  [15] = "#e5deda", /* white   */

  /* special colors */
  [256] = "#4a3c33", /* background */
  [257] = "#e5deda", /* foreground */
  [258] = "#e5deda",     /* cursor */
};

/* Default colors (colorname index)
 * foreground, background, cursor */
 unsigned int defaultbg = 0;
 unsigned int defaultfg = 257;
 unsigned int defaultcs = 258;
 unsigned int defaultrcs= 258;
