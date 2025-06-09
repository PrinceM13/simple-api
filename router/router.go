package router

import (
	"github.com/go-chi/chi/v5"
	"github.com/PrinceM13/simple-api/handler"
)

func SetupRouter() *chi.Mux {
	r := chi.NewRouter()

	r.Get("/users", handler.GetUsers)
	r.Post("/users", handler.CreateUser)

	return r
}
