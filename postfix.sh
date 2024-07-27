#!/bin/sh

source="$1"

for f in "$source"/*; do
#On MacOS compiler complains of an ambiguity between TH2::Fill(Double_t x, const char *namey, Double_t w) and TProfile2D::Fill(Double_t x, const char *namey, Double_t z, Double_t w = 1.) and similarly for the methods taken two character strings
    sed -i '
    s/t\.method("Fill", \[\](TProfile2D& a, Double_t arg0, const char \* arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D\& a, Double_t arg0, const char * arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2, 1.); });/
    s/t\.method("Fill", \[\](TProfile2D\* a, Double_t arg0, const char \* arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D* a, Double_t arg0, const char * arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2, 1.); });/
    s/t\.method("Fill", \[\](TProfile2D& a, const char \* arg0, Double_t arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D\& a, const char * arg0, Double_t arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2, 1.); });/
    s/t\.method("Fill", \[\](TProfile2D\* a, const char \* arg0, Double_t arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D* a, const char * arg0, Double_t arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2, 1.); });/
    s/t\.method("Fill", \[\](TProfile2D& a, const char \* arg0, const char \* arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D\& a, const char * arg0, const char * arg1, Double_t arg2)->Int_t { return a.Fill(arg0, arg1, arg2, 1.); });/
    s/t\.method("Fill", \[\](TProfile2D\* a, const char \* arg0, const char \* arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2); });/t.method("Fill", [](TProfile2D* a, const char * arg0, const char * arg1, Double_t arg2)->Int_t { return a->Fill(arg0, arg1, arg2, 1.); });/' "$f"
done
