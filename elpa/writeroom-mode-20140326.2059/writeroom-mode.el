;;; writeroom-mode.el --- Minor mode for distraction-free writing  -*- lexical-binding: t -*-

;; Copyright (c) 2012-2014 Joost Kremers

;; Author: Joost Kremers <joostkremers@fastmail.fm>
;; Maintainer: Joost Kremers <joostkremers@fastmail.fm>
;; Created: 11 July 2012
;; Version: 2.0
;; Keywords: text

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions
;; are met:
;;
;; 1. Redistributions of source code must retain the above copyright
;;    notice, this list of conditions and the following disclaimer.
;; 2. Redistributions in binary form must reproduce the above copyright
;;    notice, this list of conditions and the following disclaimer in the
;;    documentation and/or other materials provided with the distribution.
;; 3. The name of the author may not be used to endorse or promote products
;;    derived from this software without specific prior written permission.
;;
;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
;; IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
;; OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
;; IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
;; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
;; NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES ; LOSS OF USE,
;; DATA, OR PROFITS ; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
;; THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

;;; Commentary:

;; writeroom-mode is a minor mode for Emacs that implements a
;; distraction-free writing mode similar to the famous Writeroom editor for
;; OS X. writeroom-mode is meant for GNU Emacs 24 and isn't tested on older
;; versions.
;;
;; See the README or info manual for usage instructions.
;;
;;; Code:

(defvar writeroom--buffers nil
  "List of buffers in which `writeroom-mode' is activated.")

(defgroup writeroom nil "Minor mode for distraction-free writing."
  :group 'wp
  :prefix "writeroom-")

(defcustom writeroom-width 80
  "Width of the writeroom writing area."
  :group 'writeroom
  :type '(choice (integer :label "Absolute width:")
                 (float :label "Relative width:" :value 0.5)))

(defcustom writeroom-disable-mode-line t
  "Whether to disable the mode line in writeroom buffers."
  :group 'writeroom
  :type 'boolean)

(defvar writeroom--mode-line nil
  "Contents of `mode-line-format' before disabling the mode line.
Used to restore the mode line after disabling `writeroom-mode'.")
(make-variable-buffer-local 'writeroom--mode-line)

(defcustom writeroom-disable-fringe t
  "Whether to disable the left and right fringes when writeroom is activated."
  :group 'writeroom
  :type 'boolean)

(defcustom writeroom-maximize-window t
  "Whether to maximize the current window in its frame.
When set to `t', `writeroom-mode' deletes all other windows in
the current frame."
  :group 'writeroom
  :type '(choice (const :tag "Maximize window" t)
                 (const :tag "Do not maximize window" nil)))

(defcustom writeroom-fullscreen-effect 'fullboth
  "Effect applied when enabling fullscreen.
The value can be `fullboth', in which case fullscreen is
activated, or `maximized', in which case the relevant frame is
maximized but window decorations are still available."
  :group 'writeroom
  :type '(choice (const :tag "Fullscreen" fullboth)
                 (const :tag "Maximized" maximized)))

(defcustom writeroom-border-width 30
  "Width in pixels of the border.
To use this option, select the option \"Add border\" in `Global
Effects'. This adds a border around the text area."
  :group 'writeroom
  :type '(integer :tag "Border width"))

(define-obsolete-variable-alias 'writeroom-global-functions 'writeroom-global-effects "`writeroom-mode' version 2.0")

(defcustom writeroom-major-modes '(text-mode)
  "List of major modes in which writeroom-mode is activated.
This option is only relevant when activating `writeroom-mode'
with `global-writeroom-mode'."
  :group 'writeroom
  :type '(repeat (symbol :tag "Major mode")))

(defcustom writeroom-global-effects '(writeroom-toggle-fullscreen
                                      writeroom-toggle-alpha
                                      writeroom-toggle-vertical-scroll-bars
                                      writeroom-toggle-menu-bar-lines
                                      writeroom-toggle-tool-bar-lines)
  "List of global effects for `writeroom-mode'.
These effects are enabled when `writeroom-mode' is activated in
the first buffer and disabled when it is deactivated in the last
buffer."
  :group 'writeroom
  :type '(set (const :tag "Fullscreen" writeroom-toggle-fullscreen)
              (const :tag "Disable transparency" writeroom-toggle-alpha)
              (const :tag "Disable menu bar" writeroom-toggle-menu-bar-lines)
              (const :tag "Disable tool bar" writeroom-toggle-tool-bar-lines)
              (const :tag "Disable scroll bar" writeroom-toggle-vertical-scroll-bars)
              (const :tag "Add border" writeroom-toggle-internal-border-width)
              (repeat :inline t :tag "Custom effects" function)))

(defmacro define-writeroom-global-effect (fp value)
  "Define a global effect.
The effect is activated by setting frame parameter FP to VALUE.
FP should be an unquoted symbol, the name of a frame parameter;
VALUE must be quoted (unless it is a string or a number, of
course). It can also be an unquoted symbol, in which case it
should be the name of a global variable whose value is then
assigned to FP.

This macro defines a function `writeroom-toggle-<FP>' that takes
one argument and activates the effect if this argument is `t' and
deactivates it when it is `nil'. When the effect is activated,
the original value of frame parameter FP is stored in a frame
parameter `writeroom-<FP>', so that it can be restored when the
effect is deactivated."
  (declare (indent defun))
  (let ((wfp (intern (format "writeroom-%s" fp))))
    `(fset (quote ,(intern (format "writeroom-toggle-%s" fp)))
           #'(lambda (arg)
               (if arg
                   (progn
                     (set-frame-parameter nil (quote ,wfp) (frame-parameter nil (quote ,fp)))
                     (set-frame-parameter nil (quote ,fp) ,value))
                 (set-frame-parameter nil (quote ,fp) (frame-parameter nil (quote ,wfp)))
                 (set-frame-parameter nil (quote ,wfp) nil))))))

(define-writeroom-global-effect fullscreen writeroom-fullscreen-effect)
(define-writeroom-global-effect alpha '(100 100))
(define-writeroom-global-effect vertical-scroll-bars nil)
(define-writeroom-global-effect menu-bar-lines 0)
(define-writeroom-global-effect tool-bar-lines 0)
(define-writeroom-global-effect internal-border-width writeroom-border-width)

(defun turn-on-writeroom-mode ()
  "Turn on `writeroom-mode'.
This function activates `writeroom-mode' in a buffer if that
buffer's major mode is a member of `writeroom-major-modes'."
  (if (memq major-mode writeroom-major-modes)
      (writeroom-mode 1)))

;;;###autoload
(define-minor-mode writeroom-mode
  "Minor mode for distraction-free writing."
  :init-value nil :lighter nil :global nil
  (if writeroom-mode
      (writeroom--enable)
    (writeroom--disable)))

;;;###autoload
(define-globalized-minor-mode global-writeroom-mode writeroom-mode turn-on-writeroom-mode
  :require 'writeroom-mode
  :group 'writeroom)

(defun writeroom--kill-buffer-function ()
  "Function to run when killing a buffer.
This function checks if `writeroom-mode' is enabled in the buffer
to be killed and adjusts `writeroom--buffers' and the global
effects accordingly."
  (when writeroom-mode
    (setq writeroom--buffers (delq (current-buffer) writeroom--buffers))
    (when (not writeroom--buffers)
      (writeroom--activate-global-effects nil))))

(add-hook 'kill-buffer-hook #'writeroom--kill-buffer-function)

(defun writeroom--activate-global-effects (arg)
  "Activate or deactivate global effects.
The effects are activated if ARG is non-nil, and deactivated
otherwise."
  (mapc #'(lambda (fn)
            (funcall fn arg))
        writeroom-global-effects))

(defun writeroom--adjust-window (&optional arg window)
  "Adjust WINDOW's margin and fringes.
If ARG is omitted or nil, the margins are set according to
`writeroom-width' and the fringes are disabled. If ARG is any
other value, the margins are set to 0 and the fringes are
enabled. WINDOW defaults to the selected window."
  ;; Note: this function is used in the buffer-local value of
  ;; window-configuration-change-hook, but only in buffers where
  ;; writeroom-mode is active, so we don't need to check if writeroom-mode
  ;; is really active.
  (or window
      (setq window (selected-window)))
  (if arg
      (progn
        (writeroom--set-fringes window t)
        (writeroom--set-margins window 0))
    (writeroom--set-fringes window nil)
    (writeroom--set-margins window nil)))

(defun writeroom--set-margins (window margin)
  "Set/unset window margins for WINDOW.
If MARGIN is nil, the margins are set according to
`writeroom-width', otherwise the margins are set to MARGIN."
  (or margin
      (let ((current-width (window-total-width window)))
        (setq margin
              (cond
               ((integerp writeroom-width)
                (/ (- current-width writeroom-width) 2))
               ((floatp writeroom-width)
                (/ (- current-width (truncate (* current-width writeroom-width))) 2))))))
  (set-window-margins window margin margin))

(defun writeroom--set-fringes (window arg)
  "Enable or disable WINDOW's fringes.
If ARG is nil, the fringes are disabled. Any other value enables
them."
  (when writeroom-disable-fringe
    (if arg
        (set-window-fringes window nil nil)
      (set-window-fringes window 0 0))))

(defun writeroom--enable ()
  "Set up writeroom-mode for the current buffer.
This function sets the margins, disables the mode line and the
fringes, and maximizes the window. It also runs the functions in
`writeroom-global-effects' if the current buffer is the first
buffer in which `writeroom-mode' is activated."
  (when (not writeroom--buffers)
    (writeroom--activate-global-effects t))
  (add-to-list 'writeroom--buffers (current-buffer))
  (add-hook 'window-configuration-change-hook 'writeroom--adjust-window nil t)
  (when writeroom-maximize-window
    (delete-other-windows))
  (when writeroom-disable-mode-line
    (setq writeroom--mode-line mode-line-format)
    (setq mode-line-format nil))
  ;; if the current buffer is displayed in some window, the windows'
  ;; margins and fringes must be adjusted.
  (mapc #'(lambda (w)
            (writeroom--adjust-window nil w))
        (get-buffer-window-list (current-buffer) nil)))

(defun writeroom--disable ()
  "Reset the current buffer to its normal appearance.
This function sets the margins to 0 and reenables the mode line
and the fringes. It also runs the functions in
`writeroom-global-effects' to undo their effects if
`writeroom-mode' is deactivated in the last buffer in which it
was active."
  (setq writeroom--buffers (delq (current-buffer) writeroom--buffers))
  (when (not writeroom--buffers)
    (writeroom--activate-global-effects nil))
  (remove-hook 'window-configuration-change-hook 'writeroom--adjust-window t)
  (when writeroom-disable-mode-line
    (setq mode-line-format writeroom--mode-line)
    (setq writeroom--mode-line nil))
  ;; if the current buffer is displayed in some window, the windows'
  ;; margins and fringes must be adjusted.
  (mapc #'(lambda (w)
            (writeroom--adjust-window t w))
        (get-buffer-window-list (current-buffer) nil)))

(provide 'writeroom-mode)

;;; writeroom-mode ends here
