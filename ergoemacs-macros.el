;;; ergoemacs-macros.el --- Macros for ergoemacs-mode

;; Copyright © 2013, 2014  Free Software Foundation, Inc.

;; Maintainer: Matthew L. Fidler
;; Keywords: convenience

;; ErgoEmacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; ErgoEmacs is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ErgoEmacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;; Todo:

;; 

;;; Code:

;; These should only be called when byte compiled

;;;###autoload
(defmacro ergoemacs-with-ergoemacs (&rest body)
  "With basic `ergoemacs-mode' mode keys.
major-mode, minor-mode, and global keys are ignored."
  `(let ((ergoemacs-mode t)
         (ergoemacs-unbind-keys t)
         (ergoemacs-shortcut-keys t)
         ergoemacs-modal
         ergoemacs-read-input-keys
         (minor-mode-map-alist
          `((ergoemacs-mode ,@ergoemacs-keymap)
            (ergoemacs-unbind-keys ,@ergoemacs-unbind-keymap)))
         (ergoemacs-emulation-mode-map-alist '())
         (ergoemacs-shortcut-emulation-mode-map-alist
          `((ergoemacs-shortcut-keys ,@ergoemacs-shortcut-keymap)))
         (old-global-map (current-global-map))
         (old-local-map (current-local-map))
         (new-local-map (make-sparse-keymap))
         (new-global-map (make-sparse-keymap)))
     (unwind-protect
         (progn
           (use-global-map new-global-map)
           (use-local-map new-local-map)
           ,@body)
       (use-global-map old-global-map)
       (use-local-map old-local-map))))t

;;;###autoload
(defmacro ergoemacs-with-overrides (&rest body)
  "With the `ergoemacs-mode' mode overrides.
The global map is ignored, but major/minor modes keymaps are included."
  `(let (ergoemacs-mode
         ergoemacs-unbind-keys
         ergoemacs-shortcut-keys
         ergoemacs-modal
         ergoemacs-read-input-keys
         (old-global-map (current-global-map))
         (new-global-map (make-sparse-keymap)))
     (unwind-protect
         (progn
           (use-global-map new-global-map)
           ,@body)
       (use-global-map old-global-map))))

;;;###autoload
(defmacro ergoemacs-with-global (&rest body)
  "With global keymap, not ergoemacs keymaps."
  `(ergoemacs-without-emulation
    (let (ergoemacs-mode ergoemacs-unbind-keys)
      ,@body)))

;;;###autoload
(defmacro ergoemacs-with-major-and-minor-modes (&rest body)
  "Without global keymaps and ergoemacs keymaps."
  `(let ((old-global-map (current-global-map))
         (new-global-map (make-sparse-keymap)))
     (unwind-protect
         (progn
           (use-global-map new-global-map)
           (ergoemacs-with-global
            ,@body))
       (use-global-map old-global-map))))

;;;###autoload
(defmacro ergoemacs-without-emulation (&rest body)
  "Without keys defined at `emulation-mode-map-alists'.

Also temporarily remove any changes ergoemacs-mode made to:
- `overriding-terminal-local-map'
- `overriding-local-map'

Will override any ergoemacs changes to the text properties by temporarily
installing the original keymap above the ergoemacs-mode installed keymap.
"
  `(let ((overriding-terminal-local-map overriding-terminal-local-map)
         (overriding-local-map overriding-local-map)
         lookup tmp-overlay override-text-map)
     ;; Remove most of ergoemacs-mode's key bindings
     (ergoemacs-emulations 'remove)
     (unwind-protect
         (progn
           ;; Install override-text-map changes above anything already
           ;; installed.
           (setq tmp-overlay (ergoemacs-remove-shortcuts t))
           ,@body)
       (when tmp-overlay
         (delete-overlay tmp-overlay))
       (when ergoemacs-mode
         (ergoemacs-emulations)))))

;; This shouldn't be called at run-time; This fixes the byte-compile warning.
(fset 'ergoemacs-theme-component--parse
      #'(lambda(keys-and-body &optional skip-first)
          "Parse KEYS-AND-BODY, optionally skipping the name and
documentation with SKIP-FIRST.

Uses `ergoemacs-theme-component--parse-keys-and-body' and
  `ergoemacs-theme-component--parse-remaining'."
          (ergoemacs-theme-component--parse-keys-and-body
           keys-and-body
           'ergoemacs-theme-component--parse-remaining
           skip-first)))

;;;###autoload
(defun ergoemacs-theme-component--parse-remaining (remaining)
  "In parsing, this function converts
- `define-key' is converted to `ergoemacs-define-key' and keymaps are quoted
- `global-set-key' is converted to `ergoemacs-define-key' with keymap equal to `global-map'
- `global-unset-key' is converted to `ergoemacs-define-key' with keymap equal to `global-map' and function definition is `nil'
- `global-reset-key' is converted `ergoemacs-define-key'
- `setq' and `set' is converted to `ergoemacs-set'
- `add-hook' and `remove-hook' is converted to `ergoemacs-set'
- Mode initialization like (delete-selection-mode 1)
  or (delete-selection) is converted to
  `ergoemacs-set'
- Allows :version statement expansion
- Adds with-hook syntax or (when -hook) or (when -mode)
"
  (let* ((last-was-version nil)
         (remaining
          (mapcar
           (lambda(elt)
             (cond
              (last-was-version
               (setq last-was-version nil)
               (if (stringp elt)
                   `(ergoemacs-theme-component--version ,elt)
                 `(ergoemacs-theme-component--version ,(symbol-name elt))))
              ((ignore-errors (eq elt ':version))
               (setq last-was-version t)
               nil)
              ((ignore-errors (eq (nth 0 elt) 'global-reset-key))
               `(ergoemacs-define-key 'global-map ,(nth 1 elt) nil))
              ((ignore-errors (eq (nth 0 elt) 'global-unset-key))
               `(ergoemacs-define-key 'global-map ,(nth 1 elt) nil))
              ((ignore-errors (eq (nth 0 elt) 'set))
               ;; Currently doesn't support (setq a b c d ), but it should.
               `(ergoemacs-set ,(nth 1 elt) '(lambda() ,(nth 2 elt))))
              ((ignore-errors (eq (nth 0 elt) 'add-hook))
               `(ergoemacs-set ,(nth 1 elt) ,(nth 2 elt)
                               (list t ,(nth 3 elt) ,(nth 4 elt))))
              ((ignore-errors (eq (nth 0 elt) 'remove-hook))
               `(ergoemacs-set ,(nth 1 elt) ,(nth 2 elt)
                               (list nil nil ,(nth 3 elt))))
              ((ignore-errors (eq (nth 0 elt) 'setq))
               (let ((tmp-elt elt)
                     (ret '()))
                 (pop tmp-elt)
                 (while (and (= 0 (mod (length tmp-elt) 2)) (< 0 (length tmp-elt)))
                   (push `(ergoemacs-set (quote ,(pop tmp-elt)) '(lambda() ,(pop tmp-elt))) ret))
                 (push 'progn ret)
                 ret))
              ((ignore-errors (string-match "-mode$" (symbol-name (nth 0 elt))))
               `(ergoemacs-set (quote ,(nth 0 elt)) '(lambda() ,(nth 1 elt))))
              ((ignore-errors (eq (nth 0 elt) 'global-set-key))
               (if (ignore-errors (keymapp (symbol-value (nth 2 elt))))
                   `(ergoemacs-define-key 'global-map ,(nth 1 elt) (quote ,(nth 2 elt)))
                 `(ergoemacs-define-key 'global-map ,(nth 1 elt) ,(nth 2 elt))))
              ((ignore-errors (eq (nth 0 elt) 'define-key))
               (if (equal (nth 1 elt) '(current-global-map))
                   (if (ignore-errors (keymapp (symbol-value (nth 3 elt))))
                       `(ergoemacs-define-key 'global-map ,(nth 2 elt) (quote ,(nth 3 elt)))
                     `(ergoemacs-define-key 'global-map ,(nth 2 elt) ,(nth 3 elt)))
                 (if (ignore-errors (keymapp (symbol-value (nth 3 elt))))
                     `(ergoemacs-define-key (quote ,(nth 1 elt)) ,(nth 2 elt) (quote ,(nth 3 elt)))
                   `(ergoemacs-define-key (quote ,(nth 1 elt)) ,(nth 2 elt) ,(nth 3 elt)))))
              ((or (ignore-errors (eq (nth 0 elt) 'with-hook))
                   (and (ignore-errors (eq (nth 0 elt) 'when))
                        (ignore-errors (string-match "-\\(hook\\|mode\\)$" (symbol-name (nth 1 elt))))))
               (let ((tmp (ergoemacs-theme-component--parse (cdr (cdr elt)) t)))
                 `(ergoemacs-theme-component--with-hook
                   ',(nth 1 elt) ',(nth 0 tmp)
                   '(lambda () ,@(nth 1 tmp)))))
              (t elt)))
           remaining)))
    remaining))

;;;###autoload
(defmacro ergoemacs-theme-component (&rest body-and-plist)
  "A component of an ergoemacs-theme."
  (declare (doc-string 2)
           (indent 2))
  (let ((kb (make-symbol "body-and-plist")))
    (setq kb (ergoemacs-theme-component--parse body-and-plist))
    `(puthash ,(plist-get (nth 0 kb) ':name)
              (lambda() ,(plist-get (nth 0 kb) ':description)
                (ergoemacs-theme-component--create-component
                 ',(nth 0 kb)
                 '(lambda () ,@(nth 1 kb)))) ergoemacs-theme-comp-hash)))

(defmacro ergoemacs-test-layout (&rest keys-and-body)
  (let ((kb (make-symbol "body-and-plist"))
        (plist (make-symbol "plist"))
        (body (make-symbol "body")))
    (setq kb (ergoemacs-theme-component--parse-keys-and-body keys-and-body  nil t)
          plist (nth 0 kb)
          body (nth 1 kb))
    `(let ((old-ergoemacs-theme ergoemacs-theme)
           (macro
            ,(if (plist-get plist ':macro)
                 `(edmacro-parse-keys ,(plist-get plist ':macro) t)))
           (old-ergoemacs-keyboard-layout ergoemacs-keyboard-layout))
       (ergoemacs-mode -1)
       (setq ergoemacs-theme ,(plist-get plist ':theme))
       (setq ergoemacs-keyboard-layout ,(or (plist-get plist ':layout) "us"))
       (ergoemacs-mode 1)
       ,(if (plist-get plist :cua)
            `(cua-mode 1))
       (unwind-protect
           (progn
             ,@body)
         (ergoemacs-mode -1)
         (setq ergoemacs-theme old-ergoemacs-theme)
         (setq ergoemacs-keyboard-layout old-ergoemacs-keyboard-layout)
         (ergoemacs-mode 1)))))

(fset 'ergoemacs-theme-component--parse-keys-and-body
      #'(lambda (keys-and-body &optional parse-function  skip-first)
          "Split KEYS-AND-BODY into keyword-and-value pairs and the remaining body.

KEYS-AND-BODY should have the form of a property list, with the
exception that only keywords are permitted as keys and that the
tail -- the body -- is a list of forms that does not start with a
keyword.

Returns a two-element list containing the keys-and-values plist
and the body.

This has been stolen directly from ert by Christian Ohler <ohler@gnu.org>

Afterward it was modified for use with `ergoemacs-mode' to use
additional parsing routines defined by PARSE-FUNCTION."
          (let ((extracted-key-accu '())
                last-was-version
                plist
                (remaining keys-and-body))
            ;; Allow
            ;; (component name)
            (unless (or (keywordp (first remaining)) skip-first)
              (if (condition-case nil
                      (stringp (first remaining))
                    (error nil))
                  (push `(:name . ,(pop remaining)) extracted-key-accu)
                (push `(:name . ,(symbol-name (pop remaining))) extracted-key-accu))
              (when (memq (type-of (first remaining)) '(symbol cons))
                (pop remaining))
              (when (stringp (first remaining))
                (push `(:description . ,(pop remaining)) extracted-key-accu)))
            (while (and (consp remaining) (keywordp (first remaining)))
              (let ((keyword (pop remaining)))
                (unless (consp remaining)
                  (error "Value expected after keyword %S in %S"
                         keyword keys-and-body))
                (when (assoc keyword extracted-key-accu)
                  (warn "Keyword %S appears more than once in %S" keyword
                        keys-and-body))
                (push (cons keyword (pop remaining)) extracted-key-accu)))
            (setq extracted-key-accu (nreverse extracted-key-accu))
            (when parse-function
              (setq remaining
                    (funcall parse-function remaining)))
            (setq plist (loop for (key . value) in extracted-key-accu
                              collect key
                              collect value))
            (list plist remaining))))

;;;###autoload
(defmacro ergoemacs-theme (&rest body-and-plist)
  "Define an ergoemacs-theme.
:components -- list of components that this theme uses. These can't be seen or toggled
:optional-on -- list of components that are optional and are on by default
:optional-off -- list of components that are optional and off by default
:options-menu -- Menu options list
:silent -- If this theme is \"silent\", i.e. doesn't show up in the Themes menu.

The rest of the body is an `ergoemacs-theme-component' named THEME-NAME-theme
"
  (declare (doc-string 2)
           (indent 2))
  (let ((kb (make-symbol "body-and-plist"))
        (tmp (make-symbol "tmp")))
    (setq kb (ergoemacs-theme-component--parse-keys-and-body body-and-plist))
    (setq tmp (eval (plist-get (nth 0 kb) ':components)))
    (push (intern (concat (plist-get (nth 0 kb) ':name) "-theme")) tmp)
    (setq tmp (plist-put (nth 0 kb) ':components tmp))
    (dolist (comp '(:optional-on :optional-off :options-menu))
      (setq tmp (plist-put (nth 0 kb) comp
                           (eval (plist-get (nth 0 kb) comp)))))
    
    `(let (themes silent)
       (setq themes (gethash "defined-themes" ergoemacs-theme-hash)
             silent (gethash "silent-themes" ergoemacs-theme-hash))
       (push ,(plist-get (nth 0 kb) ':name) themes)
       (push ,(plist-get (nth 0 kb) ':name) silent)
       (puthash ,(plist-get (nth 0 kb) ':name) ',tmp ergoemacs-theme-hash)
       (if ,(plist-get (nth 0 kb) ':silent)
           (puthash "silent-themes" silent ergoemacs-theme-hash)
         (puthash "defined-themes" themes ergoemacs-theme-hash))
       (ergoemacs-theme-component ,(intern (concat (plist-get (nth 0 kb) ':name) "-theme")) ()
         ,(format "Generated theme component for %s theme" (concat (plist-get (nth 0 kb) ':name) "-theme"))
         ,@(nth 1 kb)))))

;;;###autoload
(defmacro ergoemacs-deftheme (name desc based-on &rest differences)
  "Creates a theme layout for Ergoemacs keybindings -- Compatability layer.

NAME is the theme name.
DESC is the theme description
BASED-ON is the base name theme that the new theme is based on.

DIFFERENCES are the differences from the layout based on the functions.  These are based on the following functions:

`ergoemacs-key' = defines/replaces variable key with function by (ergoemacs-key QWERTY-KEY FUNCTION DESCRIPTION ONLY-FIRST)
`ergoemacs-fixed-key' = defines/replace fixed key with function by (ergoemacs-fixed-key KEY FUNCTION DESCRIPTION)
"
  (declare (indent 1))
  `(let (silent pl tmp)
     (setq pl (gethash (or ,based-on "standard") ergoemacs-theme-hash))
     (plist-put pl ':name ,(symbol-name name))
     (setq tmp (plist-get pl ':components))
     (push (intern (concat ,(symbol-name name) "-theme")) tmp)
     (setq tmp (plist-put pl ':components tmp))
     (setq silent (gethash "silent-themes" ergoemacs-theme-hash))
     (push ,(symbol-name name) silent)
     (puthash "silent-themes" silent ergoemacs-theme-hash)
     (puthash ,(symbol-name name) tmp ergoemacs-theme-hash)
     (ergoemacs-theme-component ,(intern (concat (symbol-name name) "-theme")) ()
       ,(format "Generated theme component for %s theme" (symbol-name name))
       ,@differences)))

(defmacro ergoemacs-object-name-string (obj)
  "Compatability fixes for `object-name-string' or `eieio-object-name-string'.
"
  `(,(cond
      ((and (<= 24 emacs-major-version)
            (<= 4 emacs-minor-version))
       'eieio-object-name-string)
      (t 'object-name-string)) ,obj))

(defmacro ergoemacs-object-set-name-string (obj name)
  "Compatability fixes for `object-set-name-string' or `eieio-object-set-name-string'.
"
  `(,(cond
      ((and (<= 24 emacs-major-version)
            (<= 4 emacs-minor-version))
       'eieio-object-set-name-string)
      (t 'object-set-name-string)) ,obj ,name))

;;;###autoload
(defmacro ergoemacs-pushnew (x place &rest plist)
  "Fix byte-compile errors for emacs versions less than 24.3.
It says that `adjoin' from `cl' may be called at runtime, so use
`add-to-list' instead of `pushnew'"
  (cond
   ((and (<= 24 emacs-major-version)
         (<= 3 emacs-minor-version))
    `(pushnew ,x ,place ,@plist))
   (t `(add-to-list ',place ,x ,(plist-get plist ':test)))))

(provide 'ergoemacs-macros)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ergoemacs-macros.el ends here
